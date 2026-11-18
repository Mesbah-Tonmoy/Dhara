# The player library the app ships.
#
# media_kit's plugin bundles a libmpv of September 2023 (mpv 0.36), the last
# one its authors built; it gets no fixes any more. The app ships a current
# build in its place: one fixed archive of the Windows builds that mpv.io
# lists, checked against the SHA-256 written here. A build never uses a file
# that does not match it.
#
# To take a newer build, see "Keeping the player up to date" in README.md:
# the three values below change, and one line of
# tool/bundled-libraries.sha256.
set(DHARA_LIBMPV_ARCHIVE "mpv-dev-x86_64-20261111-git-bcde6b93cc.7z")
set(DHARA_LIBMPV_URL
  "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261111/${DHARA_LIBMPV_ARCHIVE}")
set(DHARA_LIBMPV_SHA256
  "273c079b11ea5575822f972756f4c9a71149a5c10130353abeb8586738938452")

# The archive is kept beside this file (not in git), where `flutter clean`
# does not throw it away: its source only keeps the builds of the last weeks.
set(DHARA_LIBMPV_CACHE
  "${CMAKE_CURRENT_LIST_DIR}/libmpv/${DHARA_LIBMPV_ARCHIVE}")
set(DHARA_LIBMPV_DIR
  "${CMAKE_BINARY_DIR}/dhara_libmpv/${DHARA_LIBMPV_SHA256}")
set(DHARA_LIBMPV_DLL "${DHARA_LIBMPV_DIR}/libmpv-2.dll")

if(EXISTS "${DHARA_LIBMPV_CACHE}")
  file(SHA256 "${DHARA_LIBMPV_CACHE}" DHARA_LIBMPV_HAVE)
  if(NOT DHARA_LIBMPV_HAVE STREQUAL DHARA_LIBMPV_SHA256)
    message(STATUS "The kept libmpv archive is not the pinned one; fetching it again.")
    file(REMOVE "${DHARA_LIBMPV_CACHE}")
  endif()
endif()

if(NOT EXISTS "${DHARA_LIBMPV_CACHE}")
  message(STATUS "Downloading ${DHARA_LIBMPV_URL}")
  # Stops the build if what arrives has another SHA-256.
  file(DOWNLOAD "${DHARA_LIBMPV_URL}" "${DHARA_LIBMPV_CACHE}.part"
    EXPECTED_HASH SHA256=${DHARA_LIBMPV_SHA256}
    TLS_VERIFY ON
    STATUS DHARA_LIBMPV_STATUS)
  list(GET DHARA_LIBMPV_STATUS 0 DHARA_LIBMPV_CODE)
  if(NOT DHARA_LIBMPV_CODE EQUAL 0)
    file(REMOVE "${DHARA_LIBMPV_CACHE}.part")
    message(FATAL_ERROR
      "libmpv could not be downloaded (${DHARA_LIBMPV_STATUS}). If that "
      "build is no longer offered, pin a newer one in windows/libmpv.cmake: "
      "see \"Keeping the player up to date\" in README.md.")
  endif()
  file(RENAME "${DHARA_LIBMPV_CACHE}.part" "${DHARA_LIBMPV_CACHE}")
endif()

if(NOT EXISTS "${DHARA_LIBMPV_DLL}")
  message(STATUS "Extracting libmpv-2.dll from ${DHARA_LIBMPV_ARCHIVE}")
  file(ARCHIVE_EXTRACT INPUT "${DHARA_LIBMPV_CACHE}"
    DESTINATION "${DHARA_LIBMPV_DIR}"
    PATTERNS "libmpv-2.dll")
endif()
