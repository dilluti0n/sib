# Sib tutorial and why it exists

Typical usage:

    echo 'Why did Evangelion 3.0 suddenly go off the rails?' | sib ask
    sib log
    echo 'Which of those two reasons matters more?' | sib ask

Now, the store looks like this:

    * fa754c HEAD~3 {"role":"user", "content":"Why did Evangelion 3.0 suddenly ..."}
    * b16df7 HEAD~2 {"role":"assistant", "content":"Because *Evangelion 3.0: You ..."}
    * 1c2e90 HEAD~1 {"role":"user", "content":"Which of those two reasons matters ..."}
    * 280f09 HEAD   {"role":"assistant", "content":"The **intentional creative ..."}

This is the overall concept. But why? It looks unnecessarily
complicated.

---

Let's start with basic manipulations. Forking from `HEAD~2`:

    echo 'So you mean the 14-year skip was a good decision?' | sib ask -p HEAD~2

Here, `-p HEAD~2` treats `HEAD~2` as parent instead of `HEAD`,
resulting the store changed:

    * fa754c HEAD~3 {"role":"user", "content":"Why did Evangelion 3.0 suddenly ..."}
    * b16df7 HEAD~2 {"role":"assistant", "content":"Because *Evangelion 3.0: You ..."}
    * 32e3f4 HEAD~1 {"role":"user", "content":"So you mean the 14-year skip was a ..."}
    * 8cc404 HEAD   {"role":"assistant", "content":"Artistically, yes; narratively, ..."}

The previous is at `HEAD@{1}` -- `sib switch HEAD@{1}` takes you back.

Sometimes you like your prompt, but the reply to it falls your
expectations.

    sib ask -rp HEAD~1

regenerates the reply, as `-r` means "resend" -- do not try to add
user turn.

If you're happy with the reply, give it a name:

    sib save eva-3.0-go-off
    sib save -l               # List saved names

The saved name can be addressed with `-p` (and other commands like
`sib log` ...):

    sib log eva-3.0-go-off
	echo '...' | sib ask -p eva-3.0-go-off

Each save stays in place by default and does not follow the `sib
ask`. If you like the reply as well, save it one more time.

    sib save eva-3.0-go-off

Sometimes you want opposite of `-r` -- just add input to chain, not do
LLM API call.

	curl 'https://en.wikipedia.org/w/rest.php/v1/page/Evangelion:_3.0_You_Can_(Not)_Redo/html' |
	    sib ask -c

`-c` is for that. Add enough content, and use `-r` at the end to
receive the response at the end.

Fun thing is, you can combine `-c` and `-r`. Of course, `sib ask -cr`
does not do anything, but with `-p`,

    sib ask -crp eva-3.0-go-off

takes you back to saved `eva-3.0-go-off` chain. This is same behavior
with `sib switch eva-3.0-go-off` -- than why `switch` exists?

	sib switch -f eva-3.0-go-off

makes `eva-3.0-go-off` save followes the `HEAD`. i.e. next `sib ask`
will move `eva-3.0-go-off` along with. You can always go back to
non-following state simply calling `sib switch HEAD` once.

You might get confused whether the current state is following or
not. For that reason,

	sib status

prints the status information.

Finally, if you want to start new conversation, use `-n`. It sets
empty parent.

Understanding this data model natively gives you every feature an LLM
client needs -- including [backup and
sharing](../README.md#tips). Other tools ship these as separate,
complex features you have to learn.

That's why.

## Fetch

    sib git fetch https://github.com/sib-project/hub \
        dilluti0n/why-evangelion-end-like-that:refs/conv/why-evangelion-end-like-that

    sib log why-evangelion-end-like-that

    echo 'learning to accept himself? Honestly speaking, did he really succeed?' \
        'Why is he being congratulated?' | sib ask -p why-evangelion-end-like-that
