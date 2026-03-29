#!/usr/bin/env python3
"""Score agent output quality via Anthropic API.

Usage:
  python3 tests/llm-judge.py prompt-quality profiles/coding.md
  python3 tests/llm-judge.py scorecard-quality "scorecard text..."
  python3 tests/llm-judge.py verdict-quality "verdict text..."
"""
import sys
import json

try:
    import anthropic
except ImportError:
    print("anthropic package not installed. Run: pip install anthropic")
    sys.exit(1)


def call_judge(prompt: str) -> dict:
    client = anthropic.Anthropic()
    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=512,
        messages=[{"role": "user", "content": prompt}],
    )
    text = response.content[0].text
    start = text.index("{")
    end = text.rindex("}") + 1
    return json.loads(text[start:end])


def judge_prompt_quality(content: str) -> dict:
    return call_judge(f"""Rate this agent prompt template on three dimensions (1-5 scale):

- **clarity** (1-5): Can an agent understand exactly what to do from this prompt alone?
- **completeness** (1-5): Are all requirements, output formats, and constraints specified?
- **actionability** (1-5): Can an agent produce correct, well-formatted output from this alone?

Scoring: 5=excellent (no ambiguity), 4=good (minor gaps), 3=adequate, 2=poor, 1=unusable

Respond with ONLY valid JSON: {{"clarity": N, "completeness": N, "actionability": N, "reasoning": "brief explanation"}}

Prompt to evaluate:
{content}""")


def judge_scorecard_quality(content: str) -> dict:
    return call_judge(f"""Rate this reviewer scorecard on three dimensions (1-5 scale):

- **thoroughness** (1-5): Does it evaluate all criteria with specific evidence from code?
- **specificity** (1-5): Are observations grounded in actual files, functions, and patterns?
- **fairness** (1-5): Are scores justified and consistent with the notes?

Respond with ONLY valid JSON: {{"thoroughness": N, "specificity": N, "fairness": N, "reasoning": "brief explanation"}}

Scorecard to evaluate:
{content}""")


def judge_verdict_quality(content: str) -> dict:
    return call_judge(f"""Rate this judge verdict on three dimensions (1-5 scale):

- **reasoning** (1-5): Is the decision well-justified with specific evidence?
- **specificity** (1-5): Does it reference actual code, files, and patterns?
- **decisiveness** (1-5): Is the verdict clear and actionable?

Respond with ONLY valid JSON: {{"reasoning": N, "specificity": N, "decisiveness": N, "reasoning_text": "brief explanation"}}

Verdict to evaluate:
{content}""")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    mode = sys.argv[1]
    content = sys.argv[2]

    # If content is a file path, read it
    try:
        with open(content) as f:
            content = f.read()
    except (FileNotFoundError, IsADirectoryError):
        pass  # treat as literal text

    if mode == "prompt-quality":
        result = judge_prompt_quality(content)
    elif mode == "scorecard-quality":
        result = judge_scorecard_quality(content)
    elif mode == "verdict-quality":
        result = judge_verdict_quality(content)
    else:
        print(f"Unknown mode: {mode}")
        sys.exit(1)

    print(json.dumps(result, indent=2))
