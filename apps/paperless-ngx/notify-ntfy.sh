#!/usr/bin/env bash
curl -s \
  -H "Title: Document consumed" \
  -H "Tags: page_facing_up" \
  -d "${DOCUMENT_FILE_NAME}" \
  http://ntfy:80/paperless
