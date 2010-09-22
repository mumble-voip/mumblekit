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

To build this you need the iOS 4 SDK from Apple. The iOS 4 SDK
requires Snow Leopard.

Before starting your build, you will need to check out the re-
quired submodules.

    $ git submodule init
    $ git submodule update

This will fetch known "working" snapshot of CELT, Speex and
Protocol Buffers for Objective C.

Generating the project file
---------------------------

MumbleKit uses CMake to generate its Xcode project files. If
you're on Mac OS X, you can download CMake from the CMake
website at http://www.cmake.org/. If you're a user of Homebrew,
MacPorts or Fink, there are packages available in there, too.

To generate a MumbleKit.xcodeproj that targets iOS, use:

    $ cmake -G Xcode . -DIOS_BUILD=1

To generate a MumbleKit.xcodeproj that targets Mac OS X, use:

    $ cmake -G Xcode . -DMACOSX_BUILD=1

Note: There's a bug in the current (2.8.2) release of CMake that
makes it hard to generate .xcodeprojs that use the built-in
Xcode "standard architectures" for iOS (armv6 and armv7 for device
builds, i386 for simulator builds). Please see the following CMake
bug report for more info: http://www.vtk.org/Bug/view.php?id=11244

Patches for the issue:

 * http://cmake.org/gitweb?p=cmake.git;a=patch;h=a8ded533

 * http://cmake.org/gitweb?p=cmake.git;a=patch;h=0790af3b

If you use Homebrew as your package manager, the current forumla for
CMake 2.8.2 has been patched to fix these issues. Simply upgrade to
the latest version:

    $ brew install --force cmake

To work around this issue, you can pass -DBROKEN_CMAKE=1 to simply
use whatever defaults architectures CMake wants to use.

Building it (Xcode.app)
-----------------------

After generating a MumbleKit.xcodeproj for your platform, open it
and select your prefered configuration (Debug or Release). The default
build configuration for MumbleKit is Release.

Building it (command line)
--------------------------

To build from the command line, do something like this:

        $ xcodebuild -project MumbleKit.xcodeproj -sdk iphoneos4.1 -target BUILD_ALL -configuration Release

How do I include this into my Xcode project? (iOS)
--------------------------------------------------

Note: Building MumbleKit on iOS requires the iOS 4 SDK.

The easiest way to include MumbleKit with your application on iOS
is to drag the MumbleKit.xcodeproj project inside your application's project.

Then, do the following:

 * Make MumbleKitCombined a direct dependency of your application's main
   executable target.

 * Drag libMumbleCombined.a into the 'Link Against Libraries' section of your
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

 * Make MumbleKit a direct dependency of your chosen target.

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
