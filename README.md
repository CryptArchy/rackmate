Rackmate
========
A flexible content resolver, primarily meant for use with http://rackit.co
but is also thoughtfully designed so perhaps useful for your applications too.


Building Rackmate
=================
You need Ruby, GNU Make and a CC toolchain. Here are your options:

    make

This defaults to building the Rackmate daemon with the included Lua. If you
DON’T want this:

    make STANDALONE=0

But you need to make sure libspotify and lua are installed. If they are not
installed to `/usr` or `/usr/local` then you must make the relevant paths
available in your `LDFLAGS` and `CPPFLAGS`. We do not offer help with this
step.

If you want to build the Mac or Windows GUI:

    make gui

*You cannot build the Mac or Windows GUIs `STANDALONE=0`.*

GUIs for other platforms welcome as patches. We will build GUIs for KDE and
Gnome eventually, but it’s simple to do, so feel free to submit them as pull
requests.

Building for Windows has been tested with *MingW* only. It most likely will
not compile with Visual Studio due to our use of C99.

keys.c
------
Currently Rackmate won’t build without a Spotify key (this will be changed
shortly as it isn’t strictly required). You can get yours at:

    https://developer.spotify.com/technologies/libspotify/keys/

Paste the contents of the C-Code link into keys.c in the root directory of
this distribution.

Compile Errors
--------------
I *will* help you fix your compile errors. Report an issue at GitHub.


Using Rackmate
==============
If you want to use Spotify with the daemon, you will need to run it initially
like so:

    ./rackmate --user foo

Where foo is your username. Rackmate will then prompt you for your password.

The GUI apps should be intuitive.


FAQ
===
1) Why didn’t you use Luasocket?
--------------------------------
Luasocket using coroutines was problematic with all our async-code that is
in and out of the C-layer. So in the end I just wrote our own socket layer.


Author
======
[Max Howell](https://twitter.com/mxcl), a splendid chap.


License
=======
Copyright 2013 Max Howell

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
