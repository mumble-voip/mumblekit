set(SRCDIR ${PROJECT_SOURCE_DIR}/3rdparty/speex/libspeex)
set(INCDIR ${PROJECT_SOURCE_DIR}/3rdparty/speex/include)

INCLUDE_DIRECTORIES(
	${PROJECT_SOURCE_DIR}/3rdparty/speexbuild/
	${INCDIR}
	${SRCDIR}
)

ADD_DEFINITIONS(
	-DHAVE_CONFIG_H
)

ADD_LIBRARY(Speex STATIC
	${SRCDIR}/bits.c
	${SRCDIR}/cb_search.c
	${SRCDIR}/exc_5_64_table.c
	${SRCDIR}/exc_5_256_table.c
	${SRCDIR}/exc_8_128_table.c
	${SRCDIR}/exc_10_16_table.c
	${SRCDIR}/exc_10_32_table.c
	${SRCDIR}/exc_20_32_table.c
	${SRCDIR}/filters.c
	${SRCDIR}/gain_table_lbr.c
	${SRCDIR}/gain_table.c
	${SRCDIR}/hexc_10_32_table.c
	${SRCDIR}/hexc_table.c
	${SRCDIR}/high_lsp_tables.c
	${SRCDIR}/kiss_fft.c
	${SRCDIR}/kiss_fftr.c
	${SRCDIR}/lpc.c
	${SRCDIR}/lsp_tables_nb.c
	${SRCDIR}/lsp.c
	${SRCDIR}/ltp.c
	${SRCDIR}/modes_wb.c
	${SRCDIR}/modes.c
	${SRCDIR}/nb_celp.c
	${SRCDIR}/quant_lsp.c
	${SRCDIR}/sb_celp.c
	${SRCDIR}/scal.c
	${SRCDIR}/speex_callbacks.c
	${SRCDIR}/speex_header.c
	${SRCDIR}/speex.c
	${SRCDIR}/stereo.c
	${SRCDIR}/vbr.c
	${SRCDIR}/vorbis_psy.c
	${SRCDIR}/vq.c
	${SRCDIR}/window.c
)

TARGET_LINK_LIBRARIES(Speex)
SET_TARGET_PROPERTIES(Speex PROPERTIES XCODE_ATTRIBUTE_GCC_VERSION "com.apple.compilers.llvm.clang.1_0")
SET_TARGET_PROPERTIES(Speex PROPERTIES XCODE_ATTRIBUTE_GCC_C_LANGUAGE_STANDARD "c99")
SET_TARGET_PROPERTIES(Speex PROPERTIES XCODE_ATTRIBUTE_"GCC_THUMB_SUPPORT[arch=armv6]" "NO")
SET_TARGET_PROPERTIES(Speex PROPERTIES XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS "YES")
