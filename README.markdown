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

To build this you need the iPhone 3.2 SDK (the iPad SDK), or the (as of now, unreleased)
iOS 4 SDK from Apple. The iOS 4 SDK requires Snow Leopard.

Before starting your build, you will need to check out the re-
quired submodules.

        $ git submodule init
        $ git submodule update

This will fetch known "working" snapshot of CELT, Speex and
Protocol Buffers for Objective C.

Building it (Xcode.app)
-----------------------

To build using Xcode, simply open the MumbleKit Xcode project
(MumbleKit.xcodeproj in the root of the source tree) and press
Cmd-B to build.

Building it (command line)
--------------------------

To build from the command line, do something like this:

        $ xcodebuild -project MumbleKit.xcodeproj -sdk iphonesimulator3.2 -target MumbleKit -configuration Debug

How do I include this into my Xcode project? (iOS)
--------------------------------------------------

The easiest way to include MumbleKit with your application on iOS
is to drag the MumbleKit.xcodeproj project inside your application's project.

Then, do the following:

 * Make MumbleKit (iOS) a direct dependency of your application's main
   executable target.

 * Drag libMumbleKit.a into the 'Link Against Libraries' section of your
   application's main executable target.

 * Add MumbleKit's src directory as a header search path for your application's
   main executable target.

 * Add MumbleKit's dependencies as linked libraries to the executable target:
     - AudioToolbox.framework
     - CFNetwork.framework
     - Security.framework

 * The build should now work.
