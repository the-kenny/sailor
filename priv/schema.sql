begin;

drop table if exists stream_messages;

create table stream_messages (
  id text not null primary key,
  author text not null,
  sequence number not null,
  json text not null,

  UNIQUE (author, sequence)
);

create index stream_message_author_idx on stream_messages(author);
create index stream_message_sequence_idx on stream_messages(sequence);

end;