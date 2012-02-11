MumbleKit - A Mumble client framework for iOS and Mac OS X
==========================================================

What's this?
------------

This is the source code of MumbleKit - a Mumble client framework
for iOS-based devices and computers running Mac OS X.

Mumble is gaming-focused social voice chat utility. The desktop
version runs of Windows, Mac OS X, Linux and various other Unix-like
systems. Visit its website at:

 <http://mumble.info/>

Fetching dependencies
---------------------

To build this you need the latest version of Xcode from Apple.
These days, Xcode is distributed through the Mac App Store.

Before starting your build, you will need to check out the re-
quired submodules.

    $ git submodule init
    $ git submodule update

This will fetch known "working" snapshot of CELT, Speex and
Protocol Buffers for Objective C.

How do I include this into my Xcode project? (iOS, Xcode 4)
-----------------------------------------------------------

The easiest way to include MumbleKit with your application on iOS
is to drag the MumbleKit.xcodeproj project inside your application's project,
or workspace.

Then, do the following:

 * Make MumbleKit (iOS) direct dependency of your application's main
   executable target.

 * Drag libMumbleKit.a into the 'Link Binary With Libraries' section of your
   application target's build phases.

 * Add MumbleKit's src directory as a header search path for your application's
   main executable target.

 * Add MumbleKit's dependencies as linked libraries to the executable target:
     - AudioToolbox.framework
     - CFNetwork.framework
     - Security.framework

 * The build should now work.

How do I include this into my Xcode project? (Mac OS X, Xcode 4)
----------------------------------------------------------------

One way to do this is to include MumbleKit.xcodeproj inside your main project. Then:

 * Make MumbleKit (Mac) a direct dependency of your chosen target.

 * Add MumbleKit.framework to the 'Link Binary With Libraries' section of your chosen target's
   build phases.

 * Add a copy build phase. Copy MumbleKit.framework into 'Frameworks'.
