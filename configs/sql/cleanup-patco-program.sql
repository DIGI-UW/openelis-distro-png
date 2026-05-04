-- OGC-650 (LO-01-01) cleanup: remove orphan PATCO program seed
--
-- Background: mozzy11 added configs/programs/PatientGPS.json on 2026-05-01
-- (commit 339467c) as a tentative vehicle for OGC-650 patient lat/long
-- capture via the FHIR Questionnaire-driven program-additional-fields
-- mechanism. Casey + Piotr confirmed 2026-05-04 that the program-scoped
-- approach is wrong-shaped for this requirement (gates capture on
-- mutually-exclusive program selection vs. real clinical programs like
-- VL/EID/TB). Replaced by the simpler PATIENT_GPS_CAPTURE_ENABLED toggle
-- + person.gps_latitude/gps_longitude columns (Liquibase 3.5.0-021).
--
-- This script removes the live PATCO row from clinlims.program on any
-- deployment that already loaded the now-deleted PatientGPS.json. Safe to
-- run multiple times (idempotent — no error if row absent).
--
-- Run AFTER container rebuild (the JSON file is gone from the image, so
-- the program loader won't re-create the row on next startup).

DELETE FROM clinlims.program
WHERE code = 'PATCO'
  AND program_name = 'Patient Coordinates';
