Setup
=====

Dependencies are bash >= 3.2, git >= 2.33, `jq <https://jqlang.org/>`__
>= 1.6, curl, awk and coreutils.

Install
-------

Download the `release tarball
<https://github.com/dilluti0n/sib/releases/latest>`__ or clone the
repository::

    git clone https://git.dilluti0n.com/sib.git

Global install::

    sudo make install

User install::

    make PREFIX="$HOME/.local" install

    # on macOS, add this line to .zshrc and rerun terminal
    export PATH="$HOME/.local/bin:$PATH"

Man pages are installed when built; run ``make doc`` first (needs
rst2man). The release tarball ships them prebuilt.

Init
----

Init the store::

    sib init

Check the defaults::

    $ sib status
    Sib:      /home/hskim/.sib
    Vendor:   openai
    Endpoint: https://api.openai.com/v1/responses
    Model:    gpt-6-luna

    HEAD: (unborn)

Vendors
-------

The defaults work out of the box for openai. To add a vendor and
switch to it::

    sib config edit # Inspect and edit the defaults
    sib config set vendor.cyberdyne.endpoint https://api.cyberdyne.com/v1/responses
    sib config set vendor.cyberdyne.model skynet-101-arnold
    sib config set sib.vendor cyberdyne

Auth
----

Export the API key (add it to ``~/.bashrc`` to make it persist)::

    export PLM_API_KEY='sk-xxxxxx'

Or let the vendor print its auth headers, run on each request::

    sib config set vendor.cyberdyne.headerCmd \
        'printf "Authorization: Bearer %s\n" "$(pass show cyberdyne)"'

Ask
---

::

    echo 'Why did Evangelion end like that?' | sib ask
    sib ask -rp HEAD~1 -m skynet-500   # Re-ask with other model

Now, enjoy! See the `tutorial <Tutorial.rst>`__ for what else it does.
