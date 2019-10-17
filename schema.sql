create extension if not exists btree_gist;

drop schema if exists jskplan cascade;
create schema jskplan;

set search_path=jskplan,public;

create or replace function role_exists(role text)
returns boolean
as $$
begin
  return exists (
    select
    from pg_roles
    where rolname = current_user
  );
end; $$
language plpgsql;

create or replace function role_exists_in_role(role text, orgrole text)
returns boolean
as $$
declare
  x text;
begin
  return exists (
    with recursive group_users as (
      select rolname as groname,
             oid as grosysid
      from pg_roles
      where rolname = role

      union

      select pg_group.groname,
                   pg_group.grosysid
      from pg_group
      join group_users on grolist @> array[group_users.grosysid]
    )
    select
    from group_users
    where groname = orgrole
  );
end; $$
language plpgsql;

create table organization (
  organization_id text primary key check (role_exists(organization_id)),
  name text not null unique
);

create table person (
  person_id text primary key check (role_exists(person_id) and role_exists_in_role(person_id, organization_id)),
  organization_id text not null references organization,
  email text not null check (email ~ '.*@.*'),
  unique(organization_id, email),
  unique(organization_id, person_id)
);

create table issue (
  issue_id bigserial primary key,
  parent bigint references issue,
  organization_id text not null references organization,
  title text not null,
  description text,
  points integer check(points is null or points >= 0),
  completed_points integer check(points is null or points >= 0),
  reporter_id text not null,
  assignee_id text,
  status text,
  foreign key (reporter_id, organization_id) references person (person_id, organization_id),
  foreign key (assignee_id, organization_id) references person (person_id, organization_id),
  foreign key (organization_id, issue_id) references issue(organization_id, issue_id),
  unique (organization_id, issue_id)
);
alter table issue enable row level security;
create policy issue_reader on issue for select using ((
  select true
  from person
  where person_id = current_user and person.organization_id = issue.organization_id
));


create table note (
  note_id bigserial primary key,
  issue_id bigint not null references issue,
  author text not null references person,
  organization_id text not null references organization,
  created_at timestamp not null default now(),
  body text not null,
  foreign key (organization_id, author) references person(organization_id, person_id),
  foreign key (organization_id, issue_id) references issue(organization_id, issue_id)
);
create index note_issue_id_idx on note(issue_id);

create table sprint (
  sprint_id bigserial primary key,
  organization_id text not null references organization,
  during daterange,
  exclude using gist (during with &&, organization_id with =),
  unique (sprint_id, organization_id)
);
create index sprint_organization_id_idx on sprint(organization_id);
alter table sprint enable row level security;
create policy sprint_reader on sprint for select using ((
  select true
  from person
  where person_id = current_user and person.organization_id = sprint.organization_id
));

create table sprint_issue (
  organization_id text not null references organization,
  sprint_id bigint not null,
  issue_id bigint not null,
  foreign key (organization_id, sprint_id) references sprint(organization_id, sprint_id),
  foreign key (organization_id, issue_id) references issue(organization_id, issue_id),
  primary key (sprint_id, issue_id)
);
alter table sprint_issue enable row level security;
create policy sprint_issue_reader on sprint_issue for select using ((
  select true
  from person
  where person_id = current_user and person.organization_id = sprint_issue.organization_id
));

create or replace function update_points() returns trigger as $$
  declare
    old_points integer = 0;
    old_completed_points integer = 0;
  begin
    if TG_OP='UPDATE' then
      old_points = old.points;
      old_completed_points = old.completed_points;
    end if;

    update issue
    set
      points = coalesce(points, 0) - coalesce(old_points, 0) + coalesce(new.points, 0),
      completed_points = coalesce(completed_points, 0) - coalesce(old_completed_points, 0) + coalesce(new.completed_points, 0)
    where issue.issue_id = new.parent;

    return new;
  end;
$$ language plpgsql;

create trigger issue_update_points_tgr
before insert or update
on issue
for each row
execute procedure update_points();


create or replace function jskplan_create_role(role text, orgrole text, passwd text)
returns boolean
as $$
declare
  pgrole text = role || '@' || orgrole;
begin
  create role pgrole;
  grant orgrole to pgrole;
  --alter role pgrole with password passwd;
  alter role pgrole with login;
  grant connect on database jskplan to pgrole;
  grant usage on SCHEMA jskplan to pgrole;
  grant select on all tables in schema jskplan to pgrole;

  return true;
end; $$
language plpgsql;

create type issue_child as (n int, childpath text, childofprevious boolean, issue_id bigint, title text, points int, completed_points int);
create or replace function issue_children(parent_issue_id bigint)
returns setof issue_child
as $$
begin
    return query
      with recursive child_issues as (
        select 1 as n,
               to_char(issue_id, '000000') as path,
               issue_id,
               title,
               coalesce(points, 0) as points,
               coalesce(completed_points, 0) as completed_points
        from jskplan.issue
        where parent = parent_issue_id

        union

        select (child_issues.n + 1) as n,
               child_issues.path || to_char(issue.issue_id, '000000') as path,
               issue.issue_id,
               issue.title,
               coalesce(issue.points, 0) as points,
               coalesce(issue.completed_points, 0) as completed_points
        from jskplan.issue
        join child_issues on child_issues.issue_id = issue.parent
      )
      select n,
             path,
             n > (lag(n) over (order by path)) as childofprevious,
             issue_id,
             title,
             points,
             completed_points
      from child_issues
      order by path asc;
end; $$
language plpgsql;

create type issue_parent as (n int, m int, issue_id bigint, title text, points int, completed_points int);
create or replace function issue_parents(parent_issue_id bigint)
returns setof issue_parent
as $$
begin
    return query
      with recursive parent_issues as (
        select 0 as n,
               parent,
               issue_id,
               title,
               coalesce(points, 0) as points,
               coalesce(completed_points, 0) as completed_points
        from jskplan.issue
        where issue_id = parent_issue_id

        union

        select (parent_issues.n - 1) as n,
               issue.parent,
               issue.issue_id,
               issue.title,
               coalesce(issue.points, 0) as points,
               coalesce(issue.completed_points, 0) as completed_points
        from jskplan.issue
        join parent_issues on parent_issues.parent = issue.issue_id
      )
      select n,
             1+(n - min(n) over ()) as m,
             issue_id,
             title,
             points,
             completed_points
      from parent_issues
      where n < 0
      order by n asc;
end; $$
language plpgsql;
