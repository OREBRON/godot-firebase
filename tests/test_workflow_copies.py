#!/usr/bin/env python3
"""Setup steps copied between workflow jobs stay identical.

The self-hosted jobs repeat their toolchain, disk and dependency steps instead of
sharing an action, so a fix to one copy must reach every copy. Offline; reads only
repository text (the hosted runners' Python has no YAML parser).
"""
from collections import defaultdict
from itertools import takewhile
from pathlib import Path
import re
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = {path.name: path.read_text() for path in sorted((ROOT / ".github/workflows").glob("*.yml"))}


def indentation(line):
	return len(line) - len(line.lstrip())


def step_name(before, key_indent):
	"""Name of the step whose keys start at key_indent, from the lines above its key."""
	for line in reversed(before):
		if not line.strip() or line.lstrip().startswith("#"):
			continue
		item = re.match(r"( *)(- )?(.*)$", line)
		depth = len(item[1]) + len(item[2] or "")
		if depth > key_indent:
			continue
		if depth < key_indent:
			return None
		name = re.match(r"name: (.+)$", item[3])
		if name:
			return name[1]
		if item[2]:
			return None
	return None


def step_scripts(text):
	"""(name, script) of every named step with a run: script."""
	lines = text.splitlines()
	for index, line in enumerate(lines):
		run = re.match(r"( *)run: (.+)$", line)
		name = run and step_name(lines[:index], len(run[1]))
		if not name:
			continue
		script = run[2]
		if script == "|":
			body = takewhile(lambda body_line: not body_line.strip() or indentation(body_line) > len(run[1]), lines[index + 1:])
			script = textwrap.dedent("\n".join(body)).strip("\n")
		yield name, script


class WorkflowCopiesTest(unittest.TestCase):
	def test_steps_with_one_name_run_one_script(self):
		copies = defaultdict(list)
		for workflow, text in WORKFLOWS.items():
			for name, script in step_scripts(text):
				copies[name].append((workflow, script))
		self.assertTrue(any(len(found) > 1 for found in copies.values()), "the reader found no copied steps")
		for name, found in copies.items():
			for workflow, script in found[1:]:
				with self.subTest(step=name, workflow=workflow):
					self.assertEqual(script, found[0][1], "%s differs from %s; change every copy or rename the step" % (workflow, found[0][0]))

	def test_every_self_hosted_macos_job_selects_xcode_the_same_way(self):
		blocks = []
		jobs = 0
		for text in WORKFLOWS.values():
			blocks += [textwrap.dedent(block) for block in re.findall(r"^.*xcode-select -p.*\n(?:.*\n)*? *xcodebuild -version$", text, re.M)]
			jobs += text.count("runs-on: [self-hosted, macOS, ARM64]")
		self.assertEqual(len(blocks), jobs, "one Xcode selection per self-hosted macOS job")
		for block in blocks[1:]:
			self.assertEqual(block, blocks[0])


if __name__ == "__main__":
	unittest.main()
