begin;

drop table if exists stream_messages;
drop table if exists peers;
drop table if exists wanted_blobs;

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

create table peers (
  identifier text not null primary key,
  name text,
  image_blob,
  following boolean default false
);

create table wanted_blobs (
  blob text not null primary key,
  severity number not null default -1
);

end;