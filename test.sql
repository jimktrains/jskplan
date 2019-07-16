set search_path=jskplan,public;

select * from organization;

insert into organization (organization_id, name) 
  values (1, 'test org 1');

insert into person (person_id, organization_id, email) 
  values (1, 1, 'jim@jimkeener.com');

insert into issue (issue_id, organization_id, reporter_id, title)
  values (new_issue_id(), 1, 1, 'test issue 1');

select * from issue;

insert into issue (issue_id, organization_id, reporter_id, title, points)
  values (new_issue_id(1::text::ltree), 1, 1, 'test issue 2', 3);

insert into issue (issue_id, organization_id, reporter_id, title, points)
  values (new_issue_id('1.2'::ltree), 1, 1, 'test issue 3', 4);

insert into issue (issue_id, organization_id, reporter_id, title, points)
  values (new_issue_id(), 1, 1, 'test issue 3', 4);

select * from issue;
