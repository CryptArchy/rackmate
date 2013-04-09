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
