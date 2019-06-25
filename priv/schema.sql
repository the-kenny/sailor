begin;

drop table if exists stream_messages;

create table stream_messages (
  id text not null primary key,
  author text not null,
  sequence number not null,
  json text not null,

  processed boolean not null default false,

  UNIQUE (author, sequence)
);

create index stream_message_author_idx on stream_messages(author);
create index stream_message_sequence_idx on stream_messages(sequence);

-- create table processed_messages (
--   stream_id text not null references stream_messages,
--   sequence number not null
-- );

-- create table peers (
--   identifier text not null primary key,
--   following boolean default false
-- );

create table wanted_blobs(
  blob text not null primary key,
  severity number not null default -1
);

end;