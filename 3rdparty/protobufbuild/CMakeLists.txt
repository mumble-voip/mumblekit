set(SRCDIR ${PROJECT_SOURCE_DIR}/3rdparty/protobuf/objectivec)

INCLUDE_DIRECTORIES(
	${SRCDIR}/Classes
)

ADD_LIBRARY(ProtocolBuffers STATIC
	${SRCDIR}/Classes/AbstractMessage.m
	${SRCDIR}/Classes/AbstractMessage_Builder.m
	${SRCDIR}/Classes/CodedInputStream.m
	${SRCDIR}/Classes/CodedOutputStream.m
	${SRCDIR}/Classes/ExtendableMessage.m
	${SRCDIR}/Classes/ExtensionRegistry.m
	${SRCDIR}/Classes/Field.m
	${SRCDIR}/Classes/GeneratedMessage.m
	${SRCDIR}/Classes/GeneratedMessage_Builder.m
	${SRCDIR}/Classes/MutableField.m
	${SRCDIR}/Classes/TextFormat.m
	${SRCDIR}/Classes/UnknownFieldSet.m
	${SRCDIR}/Classes/UnknownFieldSet_Builder.m
	${SRCDIR}/Classes/Utilities.m
	${SRCDIR}/Classes/WireFormat.m
	${SRCDIR}/Classes/MutableExtensionRegistry.m
	${SRCDIR}/Classes/ExtendableMessage_Builder.m
	${SRCDIR}/Classes/ConcreteExtensionField.m
)

TARGET_LINK_LIBRARIES(ProtocolBuffers)
SET_TARGET_PROPERTIES(ProtocolBuffers PROPERTIES XCODE_ATTRIBUTE_GCC_VERSION "com.apple.compilers.llvm.clang.1_0")
SET_TARGET_PROPERTIES(ProtocolBuffers PROPERTIES XCODE_ATTRIBUTE_GCC_C_LANGUAGE_STANDARD "c99")
SET_TARGET_PROPERTIES(ProtocolBuffers PROPERTIES XCODE_ATTRIBUTE_GCC_PRECOMPILE_PREFIX_HEADER "YES")
SET_TARGET_PROPERTIES(ProtocolBuffers PROPERTIES XCODE_ATTRIBUTE_GCC_PREFIX_HEADER "${SRCDIR}/ProtocolBuffers_Prefix.pch")
SET_TARGET_PROPERTIES(ProtocolBuffers PROPERTIES XCODE_ATTRIBUTE_"GCC_THUMB_SUPPORT[arch=armv6]" "NO")
SET_TARGET_PROPERTIES(ProtocolBuffers PROPERTIES XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS "YES")
SET_TARGET_PROPERTIES(ProtocolBuffers PROPERTIES XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH "NO")
