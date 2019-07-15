create extension if not exists ltree;

drop schema jskplan cascade;
create schema jskplan;

set search_path=jskplan,public;


create table organization (
  organization_id bigserial primary key,
  name text not null unqiue
);

create table person (
  person_id serial primary key,
  organization_id bigint references organization(organization_id),
  email text not null check (email ~ '.*@.*'),
  hashed_password text,
  unique(organization_id, email)
);

create table issue (
  issue_id ltree primary key,
  title text not null,
  description text,
  points integer default 0 not null check(points >= 0),
  organization_id bigint references organization(organization_id),
  reporter bigint not null,
  assignee bigint,
  category text,
  status text
  foreign key (reporter, organization_id) references person (person_id, organization_id),
  foreign key (assignee, organization_id) references person (person_id, organization_id),
);

create table issue_status_transition (
  organization_id bigint references organization(organization_id),
  category text,
  old_status text,
  new_status text not null,
  primary key (organization_id, category, old_status, new_status)
);

create function issue_valid_transition() return trigger as $$
  declare
    old_status text = null;
  begin
    if TG_OP='UPDATE' then
      old_status = old.status;
      if old.category <> new.category then
        old_status = null;
      end if;
    end if;

    perform 1
    from issue_status_transition
    where
      issue_status_transition.organization_id = new.organization_id
      and
      issue_status_transition.category = new.category
      and
      issue_status_transition.old_status = old_status
      and
      issue_status_transition.new_status = new.status
    ;

    if not found then
      raise exception 'state transition not valid';
    end if;

    return new;
$$ language plpgsql;

create table note (
  note_id serial primary key,
  issue_id ltree references issue(issue_id),
  body text not null,
  author bigint references person(person_id)
);
create index note_issue_id_idx on note(issue_id);

create table sprint (
  sprint_id serial primary key,
  organization_id references organization(organization_id),
  during daterange not null,
  exclude using gist (during with &&)
);
create index sprint_organization_id_idx on sprint(organization_id);

create table sprint_issue (
  sprint_id bigint not null references sprint(sprint_id),
  issue_id bigint not null references issue(issue_id),
  primary key(sprint_id, issue_id)
);

create function sprint_issue_same_org() return trigger as $$
  begin
    perform 1
    from sprint  
    join issue
      on issue.organization_id = sprint.organization_id
    where
      sprint.sprint_id = new.sprint_id
      and
      issue.issue_id = new.issue_id
    ;
    if not found then
      raise exception 'issue and sprint must be for the same organization';
    end if;
$$ language plpgsql;

create trigger sprint_issue_same_org_constraint
before insert or update
on issue
for each row
execute procedure sprint_issue_same_org_constraint();


create sequence ltree_pk_seq;

create or replace function new_issue_id(parent ltree) returns ltree as $$
  begin
    return coalesce(parent, '')::ltree || nextval('ltree_pk_seq'::regclass)::text;
  end;
$$ language plpgsql;

create or replace function new_issue_id() returns ltree as $$
  begin
    return nextval('ltree_pk_seq'::regclass)::text;
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
    set points = points - old_points + new.points
    where issue.issue_id = subltree(new.issue_id, 0, nlevel(new.issue_id)-1);

    return new;
  end;
$$ language plpgsql;

create trigger issue_update_points_tgr
before insert or update
on issue
for each row
execute procedure update_points();
