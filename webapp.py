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
    pgrole = email + "@" + organization

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
def sprints(cursor):
    cursor.execute("SELECT * FROM jskplan.sprint")
    sprints = cursor.fetchall()
    return render_template('sprints.jinja2.html', sprints=sprints)

@app.route("/sprint/<int:sprint_id>")
@user.requires_login
def sprint(cursor, sprint_id):
    cursor.execute("SELECT * FROM jskplan.sprint WHERE sprint_id = %s", (sprint_id,))
    sprint = cursor.fetchone()
    print(sprint)

    cursor.execute("SELECT issue.* FROM jskplan.issue join jskplan.sprint_issue USING (issue_id) WHERE sprint_id = %s", (sprint_id,))
    issues = cursor.fetchall()
    return render_template('sprint.jinja2.html', sprint=sprint, issues=issues)

@app.route("/issue/<int:issue_id>")
@user.requires_login
def issue(cursor, issue_id):
    cursor.execute("SELECT * FROM jskplan.issue WHERE issue_id = %s", (issue_id,))
    issue = cursor.fetchone()

    cursor.execute("select * from jskplan.issue_parents(%s)", (issue_id,))
    parents = cursor.fetchall()

    cursor.execute("select * from jskplan.issue_children(%s)", (issue_id,))
    children = cursor.fetchall()

    cursor.execute("SELECT * FROM jskplan.note WHERE issue_id = %s", (issue_id,))
    notes = cursor.fetchall()

    return render_template('issue.jinja2.html', sprint=sprint, issue=issue, notes=notes, parents=parents, children=children)

@app.route("/<string:name>")
def hello(name):
    return render_template('hello.jinja2',name=name)

if __name__ == "__main__":
    app.run()
