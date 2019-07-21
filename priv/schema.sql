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

create index stream_messages_author_idx on stream_messages(author);
create index stream_messages_sequence_idx on stream_messages(sequence);

create table peers (
  identifier text not null primary key,
  name text,
  image_blob text
);

create table peer_contacts (
  peer text not null references peers,
  contact text not null,
  status integer not null default 1 -- 1 is following, -1 is blocking
);

create unique index peer_contacts_peer_contact_unique_idx on peer_contacts(peer, contact);

create table wanted_blobs (
  blob text not null primary key,
  severity number not null default -1
);

end;