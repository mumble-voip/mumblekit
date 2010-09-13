PROJECT(MumbleKit-CMake)
SET(NAME MumbleKit)
CMAKE_MINIMUM_REQUIRED(VERSION 2.8)

ADD_SUBDIRECTORY(3rdparty/celt-0.7.0-build)
ADD_SUBDIRECTORY(3rdparty/speexbuild)
ADD_SUBDIRECTORY(3rdparty/speexdspbuild)
ADD_SUBDIRECTORY(3rdparty/protobufbuild)
ADD_SUBDIRECTORY(3rdparty/opensslbuild)

INCLUDE_DIRECTORIES(
	src
	proto
	3rdparty/speex/include
	3rdparty/celt-0.7.0/libcelt
	3rdparty/openssl/include
	3rdparty/protobuf/objectivec/Classes/
)

ADD_LIBRARY(MumbleKit STATIC
	src/CryptState.cpp
	src/MKCertificate.m
	src/MKServerModel.m       
	src/MKChannel.m
	src/MKServerModelObject.m
	src/MKAudio.m
	src/MKConnection.m
	src/MKServices.m
	src/MKAudioInput.m
	src/MKConnectionController.m
	src/MKUser.m
	src/MKAudioOutput.m
	src/MKCryptState_openssl.mm
	src/MKPacketDataStream.m
	src/MKVersion.m
	src/MKAudioOutputSpeech.m
	src/MKAudioOutputUser.m
	src/MKReadWriteLock.m
	src/MulticastDelegate.m

	# protobuf
	proto/Descriptor.pb.m
	proto/Mumble.pb.m
	proto/ObjectivecDescriptor.pb.m
)

SET_TARGET_PROPERTIES(MumbleKit PROPERTIES XCODE_ATTRIBUTE_GCC_VERSION "com.apple.compilers.llvm.clang.1_0")
SET_TARGET_PROPERTIES(MumbleKit PROPERTIES XCODE_ATTRIBUTE_GCC_C_LANGUAGE_STANDARD "c99")
SET_TARGET_PROPERTIES(MumbleKit PROPERTIES XCODE_ATTRIBUTE_GCC_PRECOMPILE_PREFIX_HEADER "YES")
SET_TARGET_PROPERTIES(MumbleKit PROPERTIES XCODE_ATTRIBUTE_GCC_PREFIX_HEADER "src/MumbleKit.pch")

TARGET_LINK_LIBRARIES(MumbleKit)

set(CMAKE_OSX_SYSROOT iphoneos4.1)
