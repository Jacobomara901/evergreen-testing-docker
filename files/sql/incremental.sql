\if :{?edit_window}
\else
\set edit_window '10 minutes'
\endif

\o changed_bib.ids
SELECT id FROM (
    SELECT
        bre.id
    FROM
        biblio.record_entry bre
    WHERE
        bre.edit_date BETWEEN NOW() - :'edit_window'::INTERVAL AND NOW()
    UNION
    SELECT
        acn.record AS id
    FROM
        asset.call_number acn
    WHERE
        acn.edit_date BETWEEN NOW() - :'edit_window'::INTERVAL AND NOW()
    UNION
    SELECT
        acn.record AS id
    FROM
        asset.copy acp
    JOIN
        asset.call_number acn ON acn.id = acp.call_number
    WHERE
        acp.edit_date BETWEEN NOW() - :'edit_window'::INTERVAL AND NOW()
) changed
WHERE id <> -1
ORDER BY id;

\ir all_bib.sql
