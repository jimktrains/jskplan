from flask import Flask, flash, redirect, render_template, request, session, abort, url_for
from functools import wraps
import psycopg2
import user
from config import config

app = Flask(__name__)
app.secret_key = config['secrets']['app_secret_key']

@app.route("/login", methods=['GET'])
def login():
    return render_template('login.jinja2')

@app.route("/login", methods=['POST'])
def login_post():
    email = request.form['email']
    organization = request.form['organization']
    password = request.form['password']

    hash1 = user.password_hash1(email, organization, password)

    conn = user.login(email, organization, hash1)

    if conn:
        session['email'] = email
        session['organization'] = organization
        session['hash1'] = hash1.hex()

        return redirect(url_for('sprints'))
    else:
        return redirect(url_for('login'))

@app.route("/sprints")
@user.requires_login
def sprints(cursor, dbrole):
    cursor.execute("SELECT * FROM jskplan.sprint")
    sprints = cursor.fetchall()
    return render_template('sprints.jinja2.html', sprints=sprints)

@app.route("/sprint/<int:sprint_id>")
@user.requires_login
def sprint(cursor, dbrole, sprint_id):
    cursor.execute("SELECT * FROM jskplan.sprint WHERE sprint_id = %s", (sprint_id,))
    sprint = cursor.fetchone()

    cursor.execute("SELECT issue.* FROM jskplan.issue join jskplan.sprint_issue USING (issue_id) WHERE sprint_id = %s", (sprint_id,))
    issues = cursor.fetchall()
    return render_template('sprint.jinja2.html', sprint=sprint, issues=issues)

@app.route("/sprint/new")
@user.requires_login
def sprint_new(cursor, dbrole):
    return render_template('sprint_new.jinja2.html')

@app.route("/sprint/new", methods=["POST"])
@user.requires_login
def sprint_new_post(cursor, dbrole):
    insert_data = {}
    insert_data.update(request.form)
    insert_data['organization_id'] = dbrole[1]

    cursor.execute("insert into jskplan.sprint (organization_id, title, during) values (%(organization_id)s, %(title)s, ('[' || %(start)s || ',' || %(end)s || ']')::daterange) returning sprint_id", insert_data)
    sprint = cursor.fetchone()

    return redirect(url_for('sprint', sprint_id=sprint['sprint_id']))

@app.route("/issue/<int:issue_id>/edit")
@user.requires_login
def issue_edit(cursor, dbrole, issue_id):
    cursor.execute("SELECT * FROM jskplan.issue WHERE issue_id = %s", (issue_id,))
    issue = cursor.fetchone()

    return render_template('issue_edit.jinja2.html', issue=issue)

@app.route("/issue/<int:issue_id>/edit", methods=["POST"])
@user.requires_login
def issue_edit_post(cursor, dbrole, issue_id):

    insert_data = {}
    insert_data.update(request.form)
    insert_data['issue_id'] = issue_id

    if len( insert_data['points']) > 0:
        insert_data['points'] = int(insert_data['points'])
    else:
        insert_data['points'] = None

    if len( insert_data['completed_points']) > 0:
        insert_data['completed_points'] = int(insert_data['completed_points'])
    else:
        insert_data['completed_points'] = None

    cursor.execute("""UPDATE jskplan.issue
        SET
        title = %(title)s,
        points = %(points)s,
        completed_points = %(completed_points)s,
        status = %(status)s,
        description = %(description)s
        WHERE issue_id = %(issue_id)s
    """, insert_data)

    return redirect(url_for('issue', issue_id=issue_id))

@app.route("/issue/<int:issue_id>")
@user.requires_login
def issue(cursor, dbrole, issue_id):
    cursor.execute("SELECT * FROM jskplan.issue WHERE issue_id = %s", (issue_id,))
    issue = cursor.fetchone()

    cursor.execute("select * from jskplan.issue_parents(%s)", (issue_id,))
    parents = cursor.fetchall()

    cursor.execute("select * from jskplan.issue_children(%s)", (issue_id,))
    children = cursor.fetchall()

    cursor.execute("select * from jskplan.note where issue_id = %s", (issue_id,))
    notes = cursor.fetchall()

    cursor.execute("select sprint_id, title, lower(during) as start, upper(during) as end from jskplan.sprint_issue join jskplan.sprint using (sprint_id) where issue_id = %s", (issue_id,))
    sprints = cursor.fetchall()
    print(sprints)

    return render_template('issue.jinja2.html', sprint=sprint, issue=issue, notes=notes, parents=parents, children=children, sprints=sprints)

@app.route("/issue", methods=["POST"])
@user.requires_login
def issue_post(cursor, dbrole):
    insert_data = {
        "reporter_id": dbrole[0],
        "organization_id": dbrole[1],
        "title": request.form['title'],
        "parent": None,
    }
    if 'parent' in request.form:
        insert_data['parent'] = request.form['parent']

    cursor.execute("insert into jskplan.issue (reporter_id, organization_id, title, parent) values (%(reporter_id)s, %(organization_id)s, %(title)s, %(parent)s) returning issue_id", insert_data)
    issue = cursor.fetchone()

    if 'sprint_id' in request.form:
        sprint_insert_data = {
            'issue_id': issue['issue_id'],
            'sprint_id': request.form['sprint_id'],
            'organization_id': dbrole[1],
        }
        cursor.execute("insert into jskplan.sprint_issue (organization_id, sprint_id, issue_id) values (%(organization_id)s, %(sprint_id)s, %(issue_id)s)", sprint_insert_data)

    return redirect(url_for('issue', issue_id=issue['issue_id']))

@app.route("/note", methods=["POST"])
@user.requires_login
def note_post(cursor, dbrole):
    insert_data = {
        "author": dbrole[0],
        "organization_id": dbrole[1],
        "issue_id": None,
        "body": None,
    }
    if 'body' in request.form:
        insert_data['body'] = request.form['body']
    else:
        flash("Text is required")
    if 'issue_id' in request.form:
        insert_data['issue_id'] = request.form['issue_id']
    else:
        flash("Issue is required")

    cursor.execute("insert into jskplan.note (author, organization_id, issue_id, body) values (%(author)s, %(organization_id)s, %(issue_id)s, %(body)s) returning issue_id", insert_data)
    note = cursor.fetchone()

    return redirect(url_for('issue', issue_id=note['issue_id']))

@app.route("/<string:name>")
def hello(name):
    return render_template('hello.jinja2',name=name)

if __name__ == "__main__":
    app.run()
