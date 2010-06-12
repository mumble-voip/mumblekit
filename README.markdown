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

How do I include this into my Xcode project? (Mac OS X)
-------------------------------------------------------

One way to do this is to include MumbleKit.xcodeproj inside your main project. Then:

 * Make MumbleKit (Mac OS X) a direct dependency of your chosen target.

 * Add MumbleKit.framework to the 'Link Binary Against Libraries' section of your chosen target.

 * Add a copy build phase. Copy MumbleKit.framework into 'Frameworks'.

 * Add a run script build phase. This is to change the install name id of the Mumble framework, and
   to fix up the path in your own application binary. The script I use is shown below:

        APP=${CONFIGURATION_BUILD_DIR}/Mumble.app
        FWPATH=${APP}/Contents/Frameworks/
        EXECUTABLE=${APP}/Contents/MacOS/Mumble
        
        install_name_tool -change MumbleKit @executable_path/../Frameworks/MumbleKit.framework/Versions/A/MumbleKit ${EXECUTABLE}

 It's also worth noting that this procedure seemingly only works if you have a shared build directory. For my
 own Xcode setup, I have set up an XcodeBuild directory in my home directory. My Xcode preferences are set up to
 build all projects in this directory. Per-project build directories are inconvenient, because you would have to
 set the path in both your own .xcodeproj and MumbleKit.xcodeproj.

 Note: It *should* be possible to do this would a common build directory in Xcode 3.1.1+, but I have not yet gotten this
 to work myself. If you know how, or you've got this working, throw me a note. Thanks.
