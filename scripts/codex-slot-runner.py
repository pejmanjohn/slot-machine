#!/usr/bin/env python3
"""Normalize a Codex slot run into stable report and metadata artifacts."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field


STATUS_PATTERN = re.compile(r"^\*\*Status:\*\*\s*(DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT)\s*$", re.MULTILINE)


@dataclass
class CommandObservation:
    command: str
    output: str = ""


@dataclass
class RunCapture:
    thread_id: str | None = None
    agent_messages: list[str] = field(default_factory=list)
    commands: list[CommandObservation] = field(default_factory=list)
    saw_turn_completed: bool = False

    def consume(self, payload: dict[str, object]) -> None:
        candidate_thread_id = extract_thread_id(payload)
        if candidate_thread_id and not self.thread_id:
            self.thread_id = candidate_thread_id

        event_type = payload.get("type")
        if event_type == "turn.completed":
            self.saw_turn_completed = True
            return

        if event_type != "item.completed":
            return

        item = payload.get("item")
        if not isinstance(item, dict):
            return

        item_type = item.get("type")
        if item_type == "agent_message":
            text = item.get("text")
            if isinstance(text, str) and text.strip():
                self.agent_messages.append(text.strip())
        elif item_type == "command_execution":
            command = item.get("command")
            if isinstance(command, str) and command.strip():
                output = item.get("aggregated_output")
                self.commands.append(
                    CommandObservation(
                        command=command.strip(),
                        output=output.strip() if isinstance(output, str) else "",
                    )
                )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cwd", required=True, help="Working directory for codex exec")
    parser.add_argument("--prompt-file", required=True, help="Path to the prompt file")
    parser.add_argument("--events-file", required=True, help="Where to write the raw Codex JSONL stream")
    parser.add_argument("--stderr-file", required=True, help="Where to write Codex stderr")
    parser.add_argument("--result-file", required=True, help="Where to write normalized JSON metadata")
    parser.add_argument("--report-file", required=True, help="Where to write the normalized markdown report")
    parser.add_argument("--expected-output-path", help="Expected slot output path for non-git file isolation")
    parser.add_argument("--timeout-seconds", type=int, default=1800, help="Kill codex after this many seconds")
    parser.add_argument("--sandbox", default="workspace-write", help="Codex sandbox mode")
    parser.add_argument(
        "--config",
        action="append",
        default=[],
        help="Additional `codex exec -c ...` config entries",
    )
    return parser.parse_args()


def ensure_parent(path_str: str) -> None:
    pathlib.Path(path_str).parent.mkdir(parents=True, exist_ok=True)


def read_prompt(path_str: str) -> str:
    return pathlib.Path(path_str).read_text(encoding="utf-8")


def extract_thread_id(payload: dict[str, object]) -> str | None:
    direct = payload.get("thread_id") or payload.get("threadId")
    if isinstance(direct, str) and direct.strip():
        return direct.strip()

    thread = payload.get("thread")
    if isinstance(thread, dict):
        thread_id = thread.get("id")
        if isinstance(thread_id, str) and thread_id.strip():
            return thread_id.strip()

    return None


def parse_report_status(report: str) -> str | None:
    match = STATUS_PATTERN.search(report)
    return match.group(1) if match else None


def looks_like_test_command(command: str, output: str) -> bool:
    haystack = f"{command}\n{output}"
    return bool(
        re.search(
            r"\b(test|tests|pytest|vitest|jest|cargo test|go test|npm test|pnpm test|yarn test|gradle test|mvn test)\b",
            haystack,
            re.IGNORECASE,
        )
    )


def list_changed_files(cwd: str, expected_output_path: str | None = None) -> list[str]:
    try:
        result = subprocess.run(
            ["git", "-C", cwd, "status", "--short", "--untracked-files=all"],
            check=True,
            capture_output=True,
            text=True,
        )
        files: list[str] = []
        for raw_line in result.stdout.splitlines():
            line = raw_line.rstrip()
            if not line:
                continue
            path_part = line[3:].strip()
            if " -> " in path_part:
                path_part = path_part.split(" -> ", 1)[1]
            if path_part:
                files.append(path_part)
        return files
    except (FileNotFoundError, subprocess.CalledProcessError):
        if expected_output_path and os.path.exists(expected_output_path):
            try:
                return [os.path.relpath(expected_output_path, cwd)]
            except ValueError:
                return [expected_output_path]
        return []


def synthesize_report(changed_files: list[str], commands: list[CommandObservation]) -> tuple[str, str]:
    test_commands = [cmd.command for cmd in commands if looks_like_test_command(cmd.command, cmd.output)]
    status = "DONE" if test_commands else "DONE_WITH_CONCERNS"
    report_lines = [
        "## Implementer Report",
        "",
        f"**Status:** {status}",
        "",
        "**What I implemented:**",
        "- Codex completed without a structured implementer report, so this summary was synthesized from post-run inspection.",
        "",
        "**Files changed:**",
    ]
    report_lines.extend(f"- {path}" for path in changed_files)
    report_lines.extend(["", "**Test results:**"])
    if test_commands:
        report_lines.extend(f"- Observed command: {command}" for command in test_commands)
    else:
        report_lines.append("- No structured test summary was extractable from the Codex JSON stream.")
    report_lines.extend(
        [
            "",
            "**Concerns (if any):**",
            "- Codex emitted turn.completed without a structured agent_message report.",
        ]
    )
    return status, "\n".join(report_lines).rstrip() + "\n"


def build_blocked_result(
    *,
    events_file: str,
    stderr_file: str,
    report_file: str,
    failure_reason: str,
    thread_id: str | None,
    exit_code: int,
    changed_files: list[str] | None = None,
    commands: list[CommandObservation] | None = None,
) -> dict[str, object]:
    return {
        "status": "BLOCKED",
        "thread_id": thread_id,
        "report_source": "failure",
        "report_path": report_file,
        "report": "",
        "events_path": events_file,
        "stderr_path": stderr_file,
        "changed_files": changed_files or [],
        "observed_commands": [cmd.command for cmd in (commands or [])],
        "failure_reason": failure_reason,
        "exit_code": exit_code,
    }


def write_json(path_str: str, payload: dict[str, object]) -> None:
    pathlib.Path(path_str).write_text(f"{json.dumps(payload, indent=2)}\n", encoding="utf-8")


def stream_subprocess(
    cmd: list[str],
    *,
    cwd: str,
    timeout_seconds: int,
    events_file: str,
    stderr_file: str,
    capture: RunCapture,
) -> tuple[int, list[str]]:
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    q: queue.Queue[tuple[str, str | None]] = queue.Queue()
    stderr_lines: list[str] = []

    def reader(name: str, stream: subprocess.PIPE[str] | None) -> None:
        assert stream is not None
        for line in stream:
            q.put((name, line))
        q.put((name, None))

    stdout_thread = threading.Thread(target=reader, args=("stdout", proc.stdout), daemon=True)
    stderr_thread = threading.Thread(target=reader, args=("stderr", proc.stderr), daemon=True)
    stdout_thread.start()
    stderr_thread.start()

    finished = {"stdout": False, "stderr": False}
    deadline = time.monotonic() + timeout_seconds

    with open(events_file, "w", encoding="utf-8") as events_handle, open(stderr_file, "w", encoding="utf-8") as stderr_handle:
        while not all(finished.values()):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                proc.kill()
                proc.wait(timeout=2)
                raise TimeoutError(f"codex exec timed out after {timeout_seconds} seconds.")

            try:
                source, line = q.get(timeout=min(0.2, remaining))
            except queue.Empty:
                if proc.poll() is not None and not stdout_thread.is_alive() and not stderr_thread.is_alive():
                    break
                continue

            if line is None:
                finished[source] = True
                continue

            if source == "stdout":
                events_handle.write(line)
                events_handle.flush()
                try:
                    payload = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(payload, dict):
                    capture.consume(payload)
            else:
                stderr_handle.write(line)
                stderr_handle.flush()
                stderr_lines.append(line.rstrip())

    return proc.wait(timeout=2), stderr_lines


def main() -> int:
    args = parse_args()

    for path_str in [args.events_file, args.stderr_file, args.result_file, args.report_file]:
        ensure_parent(path_str)

    if shutil.which("codex") is None:
        result = build_blocked_result(
            events_file=args.events_file,
            stderr_file=args.stderr_file,
            report_file=args.report_file,
            failure_reason="Codex CLI not found on PATH.",
            thread_id=None,
            exit_code=127,
        )
        pathlib.Path(args.report_file).write_text("", encoding="utf-8")
        write_json(args.result_file, result)
        return 1

    try:
        prompt = read_prompt(args.prompt_file)
    except OSError as exc:
        result = build_blocked_result(
            events_file=args.events_file,
            stderr_file=args.stderr_file,
            report_file=args.report_file,
            failure_reason=f"Failed to read prompt file: {exc}",
            thread_id=None,
            exit_code=1,
        )
        pathlib.Path(args.report_file).write_text("", encoding="utf-8")
        write_json(args.result_file, result)
        return 1

    cmd = ["codex", "exec", "--json", "-s", args.sandbox, "--skip-git-repo-check", "-C", args.cwd]
    for config in args.config:
        cmd.extend(["-c", config])
    cmd.append(prompt)

    capture = RunCapture()
    try:
        exit_code, stderr_lines = stream_subprocess(
            cmd,
            cwd=args.cwd,
            timeout_seconds=args.timeout_seconds,
            events_file=args.events_file,
            stderr_file=args.stderr_file,
            capture=capture,
        )
    except TimeoutError as exc:
        result = build_blocked_result(
            events_file=args.events_file,
            stderr_file=args.stderr_file,
            report_file=args.report_file,
            failure_reason=str(exc),
            thread_id=capture.thread_id,
            exit_code=124,
        )
        pathlib.Path(args.report_file).write_text("", encoding="utf-8")
        write_json(args.result_file, result)
        return 1

    changed_files = list_changed_files(args.cwd, args.expected_output_path)

    if exit_code != 0:
        failure_reason = "\n".join(line for line in stderr_lines if line).strip()
        if not failure_reason:
            failure_reason = f"codex exec exited with code {exit_code}."
        result = build_blocked_result(
            events_file=args.events_file,
            stderr_file=args.stderr_file,
            report_file=args.report_file,
            failure_reason=failure_reason,
            thread_id=capture.thread_id,
            exit_code=exit_code,
            changed_files=changed_files,
            commands=capture.commands,
        )
        pathlib.Path(args.report_file).write_text("", encoding="utf-8")
        write_json(args.result_file, result)
        return 1

    if capture.agent_messages:
        report = capture.agent_messages[-1].rstrip() + "\n"
        status = parse_report_status(report) or "DONE_WITH_CONCERNS"
        result = {
            "status": status,
            "thread_id": capture.thread_id,
            "report_source": "agent_message",
            "report_path": args.report_file,
            "report": report,
            "events_path": args.events_file,
            "stderr_path": args.stderr_file,
            "changed_files": changed_files,
            "observed_commands": [cmd.command for cmd in capture.commands],
            "failure_reason": None,
            "exit_code": exit_code,
        }
        pathlib.Path(args.report_file).write_text(report, encoding="utf-8")
        write_json(args.result_file, result)
        return 0 if status in {"DONE", "DONE_WITH_CONCERNS"} else 1

    if capture.saw_turn_completed and changed_files:
        status, report = synthesize_report(changed_files, capture.commands)
        result = {
            "status": status,
            "thread_id": capture.thread_id,
            "report_source": "post_run_inspection",
            "report_path": args.report_file,
            "report": report,
            "events_path": args.events_file,
            "stderr_path": args.stderr_file,
            "changed_files": changed_files,
            "observed_commands": [cmd.command for cmd in capture.commands],
            "failure_reason": None,
            "exit_code": exit_code,
        }
        pathlib.Path(args.report_file).write_text(report, encoding="utf-8")
        write_json(args.result_file, result)
        return 0

    if capture.saw_turn_completed:
        failure_reason = "Successful terminal event but no meaningful workspace output detected."
    else:
        failure_reason = "No successful Codex completion event detected."
    result = build_blocked_result(
        events_file=args.events_file,
        stderr_file=args.stderr_file,
        report_file=args.report_file,
        failure_reason=failure_reason,
        thread_id=capture.thread_id,
        exit_code=exit_code,
        changed_files=changed_files,
        commands=capture.commands,
    )
    pathlib.Path(args.report_file).write_text("", encoding="utf-8")
    write_json(args.result_file, result)
    return 1


if __name__ == "__main__":
    sys.exit(main())
