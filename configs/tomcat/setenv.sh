#!/bin/sh
# Sourced by $CATALINA_HOME/bin/catalina.sh immediately before the JVM is
# launched. Mounted read-only at /usr/local/tomcat/bin/setenv.sh by the
# oe.openelis.org service in docker-compose.yml.
#
# Purpose: stop Tomcat printing the database password in clear text.
#
# OpenELIS passes its datasource credentials as JVM system properties via
# CATALINA_OPTS (context.xml cannot read environment variables directly, so
# upstream has no alternative). Tomcat's VersionLoggerListener defaults to
# logArgs="true" and dumps every JVM command-line argument at INFO on each
# start, so `docker compose logs oe.openelis.org` contained:
#
#   INFO [main] ... Command line argument: -Ddatasource.password=<clear text>
#
# ...along with -Doe.ssl.keystorepassword and -Doe.ssl.truststorepassword.
# Anyone sent a log bundle for support got the site's DB credentials with it.
#
# The listener is declared in the image's conf/server.xml, which this distro
# deliberately does NOT vendor: that file also carries the TLS connector
# definitions, and freezing a copy here would silently pin them to whichever
# OE version we copied from. Instead we set logArgs="false" in place, at
# startup, on the container's own copy. conf/server.xml is owned by
# tomcat_admin (UID 8443), the account catalina.sh already runs as, so no
# privilege escalation is needed.
#
# Fails open by design: if the listener is absent or already patched (e.g.
# upstream sets logArgs itself), this is a no-op and Tomcat starts normally.
#
# Remove this file once the upstream image ships logArgs="false".

_oe_server_xml="${CATALINA_BASE:-$CATALINA_HOME}/conf/server.xml"

if [ -w "$_oe_server_xml" ] && grep -q 'VersionLoggerListener' "$_oe_server_xml" \
    && ! grep -q 'logArgs' "$_oe_server_xml"; then
    if sed -i 's|\(<Listener[[:space:]]\{1,\}className="org\.apache\.catalina\.startup\.VersionLoggerListener"\)|\1 logArgs="false"|' \
        "$_oe_server_xml" 2>/dev/null; then
        echo "[setenv] VersionLoggerListener logArgs=\"false\" (JVM arguments withheld from the log)"
    else
        echo "[setenv] WARNING: could not disable VersionLoggerListener argument logging;" >&2
        echo "[setenv]          the datasource password may appear in the Tomcat startup log." >&2
    fi
fi

unset _oe_server_xml

# catalina.sh sources this file with `.`; the last command's status becomes
# the sourcing status, so end on a deterministic success.
true
