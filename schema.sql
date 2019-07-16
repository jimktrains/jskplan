create extension if not exists ltree;
create extension if not exists btree_gist;

drop schema jskplan cascade;
create schema jskplan;

set search_path=jskplan,public;

create table organization (
  organization_id bigserial primary key,
  name text not null unique
);

create table person (
  person_id bigserial primary key,
  organization_id bigint references organization(organization_id),
  email text not null check (email ~ '.*@.*'),
  hashed_password text,
  unique(organization_id, email),
  unique(organization_id, person_id)
);

create table issue (
  issue_id ltree primary key,
  organization_id bigint references organization(organization_id),
  title text not null,
  description text,
  points integer check(points is null or points >= 0),
  reporter_id bigint not null,
  assignee_id bigint,
  status text,
  foreign key (reporter_id, organization_id) references person (person_id, organization_id),
  foreign key (assignee_id, organization_id) references person (person_id, organization_id),
  unique (issue_id, organization_id)
);

create table note (
  note_id bigserial primary key,
  issue_id ltree references issue,
  author bigint references person,
  body text not null
);
create index note_issue_id_idx on note(issue_id);

create table sprint (
  sprint_id bigserial primary key,
  organization_id bigint not null references organization,
  during daterange,
  exclude using gist (during with &&, organization_id with =),
  unique (sprint_id, organization_id)
);
create index sprint_organization_id_idx on sprint(organization_id);

create table sprint_issue (
  organization_id bigint not null references organization,
  sprint_id bigint not null,
  issue_id ltree not null,
  foreign key (organization_id, sprint_id) references sprint(organization_id, sprint_id),
  foreign key (organization_id, issue_id) references issue(organization_id, issue_id),
  primary key (sprint_id, issue_id)
);

create sequence ltree_pk_seq;

create or replace function new_issue_id(parent ltree) returns ltree as $$
  begin
    return coalesce(parent, '')::ltree || nextval('ltree_pk_seq'::regclass)::text;
  end;
$$ language plpgsql;

create or replace function new_issue_id() returns ltree as $$
  begin
    return nextval('ltree_pk_seq'::regclass)::text::ltree;
  end;
$$ language plpgsql;

create or replace function update_points() returns trigger as $$
  declare
    old_points integer = 0;
  begin
    if TG_OP='UPDATE' then
      old_points = old.points;
    end if;

    update issue
    set points = coalesce(points, 0) - coalesce(old_points, 0) + coalesce(new.points, 0)
    where issue.issue_id = subltree(new.issue_id, 0, nlevel(new.issue_id)-1);

    return new;
  end;
$$ language plpgsql;

create trigger issue_update_points_tgr
before insert or update
on issue
for each row
execute procedure update_points();
