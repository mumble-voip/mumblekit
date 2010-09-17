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

SET(SOURCES
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

SET(HEADERS
	src/MumbleKit/MKAudio.h
	src/MumbleKit/MKAudioInput.h
	src/MumbleKit/MKAudioOutput.h
	src/MumbleKit/MKAudioOutputSpeech.h
	src/MumbleKit/MKAudioOutputUser.h
	src/MumbleKit/MKCertificate.h
	src/MumbleKit/MKChannel.h
	src/MumbleKit/MKConnection.h
	src/MumbleKit/MKConnectionController.h
	src/MumbleKit/MKCryptState.h
	src/MumbleKit/MKPacketDataStream.h
	src/MumbleKit/MKReadWriteLock.h
	src/MumbleKit/MKServerModel.h
	src/MumbleKit/MKServerModelObject.h
	src/MumbleKit/MKServices.h
	src/MumbleKit/MKUser.h
	src/MumbleKit/MKUtils.h
	src/MumbleKit/MKVersion.h
)

IF (MACOSX_BUILD)
	SET(CMAKE_OSX_SYSROOT macosx10.6)
	set(CMAKE_SHARED_LINKER_FLAGS "-framework Foundation -framework AudioToolbox -framework AudioUnit -framework Security -framework CoreAudio -framework CoreServices")

	ADD_LIBRARY(MumbleKit SHARED ${SOURCES} ${HEADERS})
	TARGET_LINK_LIBRARIES(MumbleKit CELT-0.7.0 Speex SpeexDSP ProtocolBuffers OpenSSL)

	SET_TARGET_PROPERTIES(MumbleKit PROPERTIES FRAMEWORK TRUE)
	SET_TARGET_PROPERTIES(MumbleKit PROPERTIES FRAMEWORK_VERSION "1.0")
	SET_TARGET_PROPERTIES(MumbleKit PROPERTIES PUBLIC_HEADER "${HEADERS}")
ELSEIF (IOS_BUILD)
	SET(CMAKE_OSX_SYSROOT iphoneos4.1)

	ADD_LIBRARY(MumbleKit STATIC ${SOURCES} ${HEADERS})
	TARGET_LINK_LIBRARIES(MumbleKit CELT-0.7.0 Speex SpeexDSP ProtocolBuffers OpenSSL)

	# Create a combined static library that includes MumbleKit and all its
	# dependencies.
	ADD_LIBRARY(MumbleKitCombined STATIC src/dummy.c)
	TARGET_LINK_LIBRARIES(MumbleKitCombined MumbleKit)

	GET_TARGET_PROPERTY(CELT_LOCATION CELT-0.7.0 LOCATION)
	GET_TARGET_PROPERTY(SPEEX_LOCATION Speex LOCATION)
	GET_TARGET_PROPERTY(SPEEXDSP_LOCATION SpeexDSP LOCATION)
	GET_TARGET_PROPERTY(PROTOBUF_LOCATION ProtocolBuffers LOCATION)
	GET_TARGET_PROPERTY(OPENSSL_LOCATION OpenSSL LOCATION)
	GET_TARGET_PROPERTY(MUMBLEKIT_LOCATION MumbleKit LOCATION)

	GET_TARGET_PROPERTY(COMBINED_LOCATION MumbleKitCombined LOCATION)
	ADD_CUSTOM_COMMAND(TARGET MumbleKitCombined POST_BUILD
		COMMAND /usr/bin/libtool -static
			${MUMBLEKIT_LOCATION}
			${CELT_LOCATION}
			${SPEEX_LOCATION}
			${SPEEXDSP_LOCATION}
			${PROTOBUF_LOCATION}
			${OPENSSL_LOCATION}
			-o ${COMBINED_LOCATION})
endif()

SET_TARGET_PROPERTIES(MumbleKit PROPERTIES XCODE_ATTRIBUTE_GCC_VERSION "com.apple.compilers.llvm.clang.1_0")
SET_TARGET_PROPERTIES(MumbleKit PROPERTIES XCODE_ATTRIBUTE_GCC_C_LANGUAGE_STANDARD "c99")
SET_TARGET_PROPERTIES(MumbleKit PROPERTIES XCODE_ATTRIBUTE_GCC_PRECOMPILE_PREFIX_HEADER "YES")
SET_TARGET_PROPERTIES(MumbleKit PROPERTIES XCODE_ATTRIBUTE_GCC_PREFIX_HEADER "src/MumbleKit.pch")
SET_TARGET_PROPERTIES(MumbleKit PROPERTIES XCODE_ATTRIBUTE_"GCC_THUMB_SUPPORT[arch=armv6]" "NO")
SET_TARGET_PROPERTIES(MumbleKit PROPERTIES XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS "YES")

if (MACOSX_BUILD)
	SET(CMAKE_EXE_LINKER_FLAGS "-framework Foundation")
	ADD_EXECUTABLE(mkcertificate-test test/cert.m)
	TARGET_LINK_LIBRARIES(mkcertificate-test MumbleKit)
endif()
