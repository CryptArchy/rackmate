Rackmate
========
A flexible content resolver, primarily meant for use with http://rackit.co
but is also thoughtfully designed so perhaps useful for your applications too.

Max’s Release `make` Command
============================
    export SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.6.sdk/usr
    xcrun clang -march=core2 -arch i386 -arch x86_64 -O4 -Iinclude -isystem$SDK/include -mmacosx-version-min=10.5 -o rackmate `find c -name \*.c` -L$SDK/lib

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
