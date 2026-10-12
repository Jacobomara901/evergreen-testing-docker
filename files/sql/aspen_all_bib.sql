\o all_bib.ids
SELECT DISTINCT id FROM (
    SELECT
        id
    FROM
        biblio.record_entry
    WHERE
        id <> -1
        AND NOT deleted
        AND id IN (
            SELECT DISTINCT record FROM asset.call_number WHERE id IN (
                SELECT DISTINCT call_number
                FROM asset.copy acp
                JOIN asset.copy_location acpl ON (acp.location = acpl.id)
                JOIN config.copy_status ccs ON (acp.status = ccs.id)
                WHERE NOT acp.deleted
                AND   acp.opac_visible
                AND   acpl.opac_visible
                AND   ccs.opac_visible
           ) AND owning_lib IN (
                SELECT id FROM actor.org_unit WHERE opac_visible
           )
        )
) bibs
ORDER BY id;
