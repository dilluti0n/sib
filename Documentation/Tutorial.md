# Sib tutorial

Typical usage:

    echo 'Why did Evangelion 3.0 suddenly go off the rails?' | sib ask
    sib log
    echo 'Which of those two reasons matters more?' | sib ask

`sib ask` reads a prompt from stdin, sends it to the model along with
every turn reachable from `HEAD`, prints the reply to stdout, and
records both turns as two commits. `sib log` prints the whole
conversation.

Now, the store looks like this:

    * fa754c HEAD~3 {"role":"user", "content":"Why did Evangelion 3.0 suddenly ..."}
    * b16df7 HEAD~2 {"role":"assistant", "content":"Because *Evangelion 3.0: You ..."}
    * 1c2e90 HEAD~1 {"role":"user", "content":"Which of those two reasons matters ..."}
    * 280f09 HEAD   {"role":"assistant", "content":"The **intentional creative ..."}

This is the overall concept. But why? It looks unnecessarily
complicated.

---

Let's look at a command like this:

    sib ask -rp HEAD~1

What each flag does:
  - `-r`: do not read stdin; send the chain to endpoint as is
  - `-p HEAD~1`: treat `HEAD~1` as the parent instead of `HEAD`

Since your last prompt lives at `HEAD~1`, this is the same as the
'Repeat' button seen in the web UI.

Without `-r`:

    echo 'So you mean the 14-year skip was a good decision?' | sib ask -p HEAD~2

This is similar to the 'Edit' button. It forks from `HEAD~2`, as if
you edited `1c2e90` in a web UI.

    * fa754c HEAD~3 {"role":"user", "content":"Why did Evangelion 3.0 suddenly ..."}
    * b16df7 HEAD~2 {"role":"assistant", "content":"Because *Evangelion 3.0: You ..."}
    * 32e3f4 HEAD~1 {"role":"user", "content":"So you mean the 14-year skip was a ..."}
    * 8cc404 HEAD   {"role":"assistant", "content":"Artistically, yes; narratively, ..."}

Hashes are hard to remember, so name them:

    sib save eva-3.0-go-off
    sib save -l               # List saved names

The saved name can be addressed with `-p` (and other commands like
`sib log` ...):

    sib git fetch https://github.com/sib-project/hub \
        dilluti0n/why-evangelion-end-like-that:refs/conv/why-evangelion-end-like-that

    sib log why-evangelion-end-like-that

    echo 'learning to accept himself? Honestly speaking, did he really succeed?' \
        'Why is he being congratulated?' | sib ask -p why-evangelion-end-like-that

Each save stays in place by default and does not follow the `sib
ask`. If the result matches the original name and you like it, save it
one more time.

    sib save why-evangelion-end-like-that

Your Evangelion 3.0 chain is of course still there:

    sib log eva-3.0-go-off

You can pick it up again with `sib ask -p`. But sometimes you only
want to move HEAD:

    sib ask -crp eva-3.0-go-off

`-c` is new here: no API call, so no assistant turn. With `-r` there is
no input either, so all that is left is moving `HEAD`.

These cover nearly every use case for Sib.

Knowing how conversations are saved gives you Repeat, Edit, Fork,
saving conversations, and switching conversations. [Backup and
sharing](#tips) come from the same place. Other tools ship each of
them as a separate named feature. Sib does not have to.

That's why.
