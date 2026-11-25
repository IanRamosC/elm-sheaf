# Security

Please report a vulnerability privately, through GitHub's private vulnerability
reporting: open the repository's Security tab and choose "Report a
vulnerability". Don't open a public issue for it, so it can be fixed before
it's widely known.

Say what an attacker can do, and how to reproduce it: the Sheaf version, the
command you ran, and a minimal site if one is needed.

Sheaf builds sites on your machine and in CI, from content and Elm code you
control, and its output is static files. The problems that matter most are the
ones where building someone else's site, such as a cloned repository, can read
or publish files from outside it, run code it shouldn't, or put script into the
pages it writes.

Only the latest release gets security fixes. Sheaf hasn't had a release yet,
so until it does, fixes go to `main`.
