
CREATE TABLE buscribe_transcriptions
(
    id                 BIGSERIAL PRIMARY KEY,
    start_time         timestamp without time zone NOT NULL,
    end_time           timestamp without time zone NOT NULL,
    transcription_line text                        NOT NULL,
    line_speaker       float[128],
    transcription_json jsonb                       NOT NULL
);

CREATE INDEX buscribe_transcriptions_idx ON buscribe_transcriptions USING
    GIN (to_tsvector('english', transcription_line));

-- This might not actually be needed. Check once there is more data.
CREATE INDEX buscribe_start_time_idx ON buscribe_transcriptions (start_time);
CREATE INDEX buscribe_end_time_idx ON buscribe_transcriptions (end_time);

CREATE TABLE buscribe_speakers
(
    id   BIGSERIAL PRIMARY KEY,
    name text NOT NULL UNIQUE CHECK ( name != '' )
);

CREATE TABLE buscribe_verifiers
(
    email TEXT PRIMARY KEY,
    name  TEXT NOT NULL
);

CREATE TABLE buscribe_line_speakers
(
    line     BIGINT NOT NULL REFERENCES buscribe_transcriptions,
    speaker  BIGINT NOT NULL REFERENCES buscribe_speakers,
    verifier text   NOT NULL REFERENCES buscribe_verifiers,
    PRIMARY KEY (line, speaker, verifier)
);

CREATE TABLE buscribe_line_inferred_speakers
(
    line    BIGINT NOT NULL REFERENCES buscribe_transcriptions,
    speaker BIGINT NOT NULL REFERENCES buscribe_speakers,
    PRIMARY KEY (line, speaker)
);

CREATE TABLE buscribe_verified_lines
(
    line          BIGINT NOT NULL REFERENCES buscribe_transcriptions,
    verified_line TEXT   NOT NULL,
    verifier      text REFERENCES buscribe_verifiers,
    PRIMARY KEY (line, verifier)
);

-- Indexed with C weight (0.2 vs default 0.1)
CREATE INDEX buscribe_verified_lines_idx ON buscribe_verified_lines USING
    GIN (setweight(to_tsvector('english', verified_line), 'C'));

CREATE VIEW buscribe_all_transcriptions AS
SELECT buscribe_transcriptions.id,
       start_time,
       end_time,
       coalesce(buscribe_verified_lines.verifier, speakers.verifier)                AS verifier,
       names,
       coalesce(verified_line, buscribe_transcriptions.transcription_line)          AS transcription_line,
       coalesce(setweight(to_tsvector('english', verified_line), 'C'),
                to_tsvector('english', buscribe_transcriptions.transcription_line)) AS transcription_line_ts,
       setweight(to_tsvector(array_to_string(names, ' ')), 'C')                     AS names_ts,
       null                                                                         AS transcription_json
FROM buscribe_transcriptions
         LEFT OUTER JOIN buscribe_verified_lines ON buscribe_transcriptions.id = buscribe_verified_lines.line
         LEFT OUTER JOIN (
    SELECT line, verifier, array_agg(name) AS names
    FROM buscribe_line_speakers
             INNER JOIN buscribe_speakers ON buscribe_line_speakers.speaker = buscribe_speakers.id
    GROUP BY line, verifier
) AS speakers ON buscribe_transcriptions.id = speakers.line AND (
            speakers.verifier = buscribe_verified_lines.verifier OR
            buscribe_verified_lines.verifier IS NULL
    )
WHERE coalesce(buscribe_verified_lines.verifier, speakers.verifier) IS NOT NULL
UNION
SELECT id,
       start_time,
       end_time,
       null                                       AS verifier,
       names,
       transcription_line,
       to_tsvector('english', transcription_line) AS transcription_line_ts,
       null                                       AS names_ts,
       transcription_json
FROM buscribe_transcriptions
         LEFT OUTER JOIN (
    SELECT line, array_agg(name) AS names
    FROM buscribe_line_inferred_speakers
             INNER JOIN buscribe_speakers ON buscribe_line_inferred_speakers.speaker = buscribe_speakers.id
    GROUP BY line
) AS speakers ON id = speakers.line;

CREATE VIEW buscribe_all_transcriptions2 AS
SELECT buscribe_transcriptions.id,
       start_time,
       end_time,
       coalesce(buscribe_verified_lines.verifier, speakers.verifier)                AS verifier,
       names,
       coalesce(verified_line, buscribe_transcriptions.transcription_line)          AS transcription_line,
       to_tsvector('english', buscribe_transcriptions.transcription_line)           AS machine_line_ts,
       setweight(to_tsvector('english', verified_line), 'C')                        AS verified_line_ts,
       coalesce(setweight(to_tsvector('english', verified_line), 'C'),
                to_tsvector('english', buscribe_transcriptions.transcription_line)) AS transcription_line_ts,
       setweight(to_tsvector(array_to_string(names, ' ')), 'C')                     AS names_ts,
       null                                                                         AS transcription_json
FROM buscribe_transcriptions
         LEFT OUTER JOIN buscribe_verified_lines ON buscribe_transcriptions.id = buscribe_verified_lines.line
         LEFT OUTER JOIN (
    SELECT line, verifier, array_agg(name) AS names
    FROM buscribe_line_speakers
             INNER JOIN buscribe_speakers ON buscribe_line_speakers.speaker = buscribe_speakers.id
    GROUP BY line, verifier
) AS speakers ON buscribe_transcriptions.id = speakers.line AND (
            speakers.verifier = buscribe_verified_lines.verifier OR
            buscribe_verified_lines.verifier IS NULL
    )
WHERE coalesce(buscribe_verified_lines.verifier, speakers.verifier) IS NOT NULL
UNION
SELECT id,
       start_time,
       end_time,
       null                                       AS verifier,
       names,
       transcription_line,
       to_tsvector('english', transcription_line) AS machine_line_ts,
       null                                       AS verified_line_ts,
       to_tsvector('english', transcription_line) AS transcription_line_ts,
       null                                       AS names_ts,
       transcription_json
FROM buscribe_transcriptions
         LEFT OUTER JOIN (
    SELECT line, array_agg(name) AS names
    FROM buscribe_line_inferred_speakers
             INNER JOIN buscribe_speakers ON buscribe_line_inferred_speakers.speaker = buscribe_speakers.id
    GROUP BY line
) AS speakers ON id = speakers.line;

-- Convert last lexeme in a query to prefix query.
CREATE FUNCTION convert_query(query_text text) RETURNS tsquery AS
$$
DECLARE
    ws_query text := websearch_to_tsquery(query_text)::text;
BEGIN
    RETURN (CASE WHEN ws_query != '' THEN ws_query || ':*' ELSE '' END)::tsquery;
END;
$$ LANGUAGE plpgsql;
