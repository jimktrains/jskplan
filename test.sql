\pset pager
drop role if exists testorg;
drop role if exists "jim@jimkeener.com@testorg";
drop role if exists testorg2;
drop role if exists "jim@jimkeener.com@testorg2";
set search_path=jskplan,public;

select * from organization;

create role "testorg";
create role "testorg2";
insert into organization (organization_id, name)
  values ('testorg', 'test org 1'),
         ('testorg2', 'test org 2');

create role "jim@jimkeener.com@testorg";
grant "testorg" to "jim@jimkeener.com@testorg";
alter role "jim@jimkeener.com@testorg" with password 'e5ea0b5e3b0e3d7e1ff42a6bcccd3fd492ecd00740856166d870afc08d3772420a4387a1a1e91326d800e9d75dd5e50efb91507c22c65be6af30ca0de1dd3a18';
alter role "jim@jimkeener.com@testorg" with login;
grant connect on database jskplan to "jim@jimkeener.com@testorg";
grant usage on SCHEMA jskplan to "jim@jimkeener.com@testorg";
grant select on ALL TABLES IN SCHEMA jskplan to "jim@jimkeener.com@testorg";

create role "jim@jimkeener.com@testorg2";
grant "testorg2" to "jim@jimkeener.com@testorg2";
alter role "jim@jimkeener.com@testorg2" with password 'e5ea0b5e3b0e3d7e1ff42a6bcccd3fd492ecd00740856166d870afc08d3772420a4387a1a1e91326d800e9d75dd5e50efb91507c22c65be6af30ca0de1dd3a18';
alter role "jim@jimkeener.com@testorg2" with login;
grant connect on database jskplan to "jim@jimkeener.com@testorg2";
grant usage on SCHEMA jskplan to "jim@jimkeener.com@testorg2";
grant select on ALL TABLES IN SCHEMA jskplan to "jim@jimkeener.com@testorg2";


insert into person (person_id, organization_id, email)
  values ('jim@jimkeener.com@testorg', 'testorg', 'jim@jimkeener.com'),
         ('jim@jimkeener.com@testorg2', 'testorg2', 'jim@jimkeener.com');

insert into issue
(issue_id, organization_id, reporter_id,                 parent, title,         points)
values
(1,        'testorg',       'jim@jimkeener.com@testorg', null,  'test issue 1', null),
(2,        'testorg',       'jim@jimkeener.com@testorg', 1,     'test issue 2', 3),
(3,        'testorg',       'jim@jimkeener.com@testorg', 2,     'test issue 3', 4),
(4,        'testorg2',      'jim@jimkeener.com@testorg2', null, 'test issue 4', 4),
(5,        'testorg',       'jim@jimkeener.com@testorg', 2,     'test issue 5', 4),
(6,        'testorg',       'jim@jimkeener.com@testorg', 3,     'test issue 6', 4),
(7,        'testorg',       'jim@jimkeener.com@testorg', 1,     'test issue 7', 4)
;
select * from issue;

update issue set completed_points = completed_points + 2 where issue_id = 2;
select * from issue;

insert into sprint
(sprint_id, organization_id)
values
(1, 'testorg'),
(2, 'testorg2'),
(3, 'testorg')
;

insert into sprint_issue
(sprint_id, issue_id, organization_id)
values
(1, 2, 'testorg')
;

insert into note
(issue_id, author, organization_id, body)
values
(2, 'jim@jimkeener.com@testorg', 'testorg', 'this is a test')
;
