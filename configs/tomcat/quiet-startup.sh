#!/bin/sh
# Sourced by catalina.sh. Preserve the image's logging configuration while
# suppressing VersionLoggerListener, which otherwise logs password arguments.
_png_logging=$(mktemp /tmp/png-logging.XXXXXX) || exit 1
cat "${CATALINA_BASE:-$CATALINA_HOME}/conf/logging.properties" > "$_png_logging" || exit 1
printf '\norg.apache.catalina.startup.VersionLoggerListener.level = OFF\n' >> "$_png_logging"
CATALINA_LOGGING_CONFIG="-Djava.util.logging.config.file=$_png_logging"
export CATALINA_LOGGING_CONFIG
unset _png_logging
