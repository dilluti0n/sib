Tips
====

Sharing
-------

Fetch a conversation from the hub::

    sib git fetch https://github.com/sib-project/hub \
        dilluti0n/nvim-sib-log-res:refs/conv/nvim-sib-log-res

The above command copies the conversation directly to your store. You
can read it with ``sib log nvim-sib-log-res`` or continue it wherever
you want with ``sib ask -p nvim-sib-log-res``.

The reverse works too::

    sib git push <your-repo-url> <local-ref>:refs/heads/<remote-ref>

Wanna share yours with random internet dudes? Publish to
`sib-project/hub <https://github.com/sib-project/hub>`__. Push to any
public git repo as above and `open a share issue
<https://github.com/sib-project/hub/issues/new?template=share.yml>`__. It
will be automatically published to there.

Usage of sib ask
----------------

``sib ask`` has a lot of flags. That is because it does a lot of things
in the first place. Each flag changes one part of what it does, and
they combine.

For example::

    echo 'Summarize the entire context for use in the next conversation.' | sib ask
    sib show HEAD:content | sib ask -nc

``sib show HEAD:content`` prints only ``content`` field of ``HEAD``,
which is the summary just generated. ``-n`` ignores the existing ``HEAD``,
creates a new chain and switch to it. ``-c`` chains only user turns
without querying the model.

So when a conversation gets too long, this starts a fresh one while
carrying the context over.

Markdown rendering and emacs/neovim extension
---------------------------------------------

If you need Markdown rendering::

    sib log | glow -p

Or inside neovim::

    { echo Write a code which do same thing in neovim lua; echo; cat <<EOF
    (defun sib-log ()
      (interactive)
      (require 'markdown-mode)

      (let ((buf (get-buffer-create "*sib*"))
            (err (get-buffer-create "*sib-error*")))
        (async-shell-command "sib log" buf err)

        (with-current-buffer buf
          (markdown-mode)
          (font-lock-ensure))

        (pop-to-buffer buf)))
    EOF
    } | sib ask -n

To save you API usage, I've already done it for you. Set it up with
the following commands::

    sib git fetch https://github.com/sib-project/hub \
        dilluti0n/nvim-sib-log-res:refs/conv/nvim-sib-log

    sib show nvim-sib-log:content >> ~/.config/nvim/init.lua
    nvim +SibLog

Also, I checked it does the things, but I don't really know much about
Neovim or Lua. So the generated script came out at 74 lines (the elisp
above is 12) and may be hard to maintain.

The nice part is, you already have the whole conversation behind it!
So someone who actually knows their way around could pick it up from
any turn, refactor it with AI, and upload an improved version.
