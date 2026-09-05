#!/usr/bin/env python3
"""Run an agent typed in a panel shell with local status hooks; preserve arguments."""
import json
import os
import subprocess
import sys
import uuid


def main():
    source = sys.argv[1]
    argv = json.loads(os.environ['TERMINAL_PANEL_' + source.upper() + '_ARGV'])
    if not argv[0]:
        print(source + ': command not found', file=sys.stderr)
        return 127
    launch = uuid.uuid4().hex
    env = dict(os.environ)
    env['TERMINAL_PANEL_ID'] += '-' + launch

    def signal(event):
        sys.stdout.write('\x1b]777;terminal-panel;' + event + ';' + source + ';' + launch + '\x1b\\')
        sys.stdout.flush()

    signal('start')
    try:
        process = subprocess.Popen(argv + sys.argv[2:], env=env)
        while True:
            try:
                return process.wait()
            except KeyboardInterrupt:
                # The foreground process group delivers Ctrl+C to the agent too.
                # Let its own TUI decide whether to interrupt a turn or exit.
                continue
    except OSError as error:
        print(str(error), file=sys.stderr)
        return 127
    finally:
        signal('stop')


if __name__ == '__main__':
    sys.exit(main())
