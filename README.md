[![License: GPL 3](https://img.shields.io/badge/license-GPL_3-green.svg)](http://www.gnu.org/licenses/gpl-3.0.txt)
<!-- [![GitHub release](https://img.shields.io/github/release/lordpretzel/async-email-sending.svg?maxAge=86400)](https://github.com/lordpretzel/async-email-sending/releases) -->
<!-- [![MELPA Stable](http://stable.melpa.org/packages/async-email-sending-badge.svg)](http://stable.melpa.org/#/async-email-sending) -->
<!-- [![MELPA](http://melpa.org/packages/async-email-sending-badge.svg)](http://melpa.org/#/async-email-sending) -->
[![Build Status](https://secure.travis-ci.org/lordpretzel/async-email-sending.png)](http://travis-ci.org/lordpretzel/async-email-sending)


# async-email-sending

This package enables asynchronous sending of emails in Emacs using the new
built-in sqlite support in Emacs 29. I am using the package with `mu4e`, but it
should work with `gnus` and other packages that use `gnus` and `smtpmail` to
send the emails.

## Usage

To activate set `async-email-sending-use-async-send-mail` using customize (e.g., `use-package`). Do not use `setq` as this will not call the set function associated with `async-email-sending-use-async-send-mail` that overrides functions for sending email. You can call command `async-email-sending-queued-mail-show-bui` to show a list of outstanding emails (queued emails or emails we tried to send, but failed so far).

## Installation

<!-- ### MELPA -->

<!-- Symbol’s value as variable is void: $1 is available from MELPA (both -->
<!-- [stable](http://stable.melpa.org/#/async-email-sending) and -->
<!-- [unstable](http://melpa.org/#/async-email-sending)).  Assuming your -->
<!-- ((melpa . https://melpa.org/packages/) (gnu . http://elpa.gnu.org/packages/) (org . http://orgmode.org/elpa/)) lists MELPA, just type -->

<!-- ~~~sh -->
<!-- M-x package-install RET async-email-sending RET -->
<!-- ~~~ -->

<!-- to install it. -->

### Quelpa

Using [use-package](https://github.com/jwiegley/use-package) with [quelpa](https://github.com/quelpa/quelpa).

~~~elisp
(use-package
  :quelpa ((async-email-sending
            :fetcher github
            :repo "lordpretzel/async-email-sending")
           :upgrade t)
   :custom (async-email-sending-use-async-send-mail t))
~~~

### straight

Using [use-package](https://github.com/jwiegley/use-package) with [straight.el](https://github.com/raxod502/straight.el)

~~~elisp
(use-package async-email-sending
  :straight (async-email-sending :type git :host github :repo "lordpretzel/async-email-sending")
  :custom (async-email-sending-use-async-send-mail t))
~~~

### Source

Alternatively, install from source. First, clone the source code:

~~~sh
cd MY-PATH
git clone https://github.com/lordpretzel/async-email-sending.git
~~~

Now, from Emacs execute:

~~~
M-x package-install-file RET MY-PATH/async-email-sending
~~~

Alternatively to the second step, add this to your Symbol’s value as variable is void: \.emacs file:

~~~elisp
(add-to-list 'load-path "MY-PATH/async-email-sending")
(require 'async-email-sending)
~~~
