Rackmate
========
A flexible content resolver, primarily meant for use with http://rackit.co
but is also thoughtfully designed so perhaps useful for your applications too.


Building Rackmate
=================
Type `make`, or `make macos`. You will get `rackmate` or `Rackmate.app`.
Currently you cannot install the daemon nicely as the Lua is not able to be
relocated. I will fix this soon, or submit a patch.

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
