# Sib

Sib is a git-based LLM client. Each conversation is a chain of git
commits, so you can fork from any turn, save it, and fetch or push it
like any git ref.

    git clone https://git.dilluti0n.com/sib.git && cd sib
    make PREFIX="$HOME/.local" install   # or: sudo make install
    sib init
    export PLM_API_KEY='sk-xxxxxx'

Requires bash >= 3.2, git >= 2.33, [jq](https://jqlang.org/) >= 1.6,
curl, awk and coreutils.

- Setup (vendors, auth): [Documentation/Setup.rst](./Documentation/Setup.rst)
- Tutorial, and why: [Documentation/Tutorial.rst](./Documentation/Tutorial.rst)
- Tips: [Documentation/Tips.rst](./Documentation/Tips.rst)
- Trace format: [Documentation/KeyFormat.rst](./Documentation/KeyFormat.rst)
- Latest release: https://github.com/dilluti0n/sib/releases/latest
- Shared conversations: https://github.com/sib-project/hub
- Issue tracker: https://github.com/dilluti0n/sib/issues
- Email: sib-project@dilluti0n.com

## Usage

    echo 'Why did Evangelion end like that?' | sib ask
    sib log                       # read the conversation
    sib ask -rp HEAD~1            # regenerate the last reply
    echo '...' | sib ask -p HEAD~2  # fork from an earlier turn
    sib save eva                  # name it
    sib switch -f eva             # keep eva moving with sib ask
    sib status

    sib <cmd> -h

See [sibrevisions(7)](./Documentation/sibrevisions.7.rst) for how to name
chains (`HEAD~2`, `eva@{1}`, ...).

---

Copyright 2026 Hee-Suk Kim.

This program is free software, released under the GNU General Public
License, version 3 only. See [COPYING](COPYING) or
<https://www.gnu.org/licenses/>.
