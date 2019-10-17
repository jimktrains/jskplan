from functools import wraps
import psycopg2
import psycopg2.extras
from flask import Flask, flash, redirect, render_template, request, session, abort, url_for
import hashlib
import json

app = Flask(__name__)
app.secret_key = '8UXnRlmtoAu1x3Ofgt7y0xjYKm/TeIEk6Xqvx9aTrir1iC45++8nhJJ7y2UQPk5Z'

def password_hash1(user, organization, password):
    salt = hashlib.sha512(json.dumps({"user": user, "organization": organization}).encode('utf8')).digest()
    pwd = hashlib.scrypt(password.encode('utf8'), salt=salt, n=16, r=10, p=10)
    return pwd

def password_hash2(user, organization, hash1):
    salt = hashlib.sha512(json.dumps({"user": user, "organization": organization, "hash1": hash1.hex()}).encode('utf8')).digest()
    pwd = hashlib.scrypt(hash1, salt=salt, n=16, r=10, p=10)
    return pwd

def requires_login(f):
    @wraps(f)
    def inside(**kwargs):
        if 'email' not in session or \
           'organization' not in session or \
           'hash1' not in session:
            return redirect(url_for('login'))

        hash2 = password_hash2(session['email'], session['organization'], bytes.fromhex(session['hash1']))
        pgrole = session['email'] + "@" + session['organization']
        conn = psycopg2.connect(
            dbname='jskplan',
            host='127.0.0.1',
            user=pgrole,
            password=hash2.hex()
        )
        with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cursor:
            return f(cursor, **kwargs)
    return inside

@app.route("/login", methods=['GET'])
def login():
    return render_template('login.jinja2')

@app.route("/login", methods=['POST'])
def login_post():
    email = request.form['email']
    organization = request.form['organization']
    password = request.form['password']
    pgrole = email + "@" + organization

    hash1 = password_hash1(email, organization, password)
    hash2 = password_hash2(email, organization, hash1)

    conn = psycopg2.connect(
        dbname='jskplan',
        host='127.0.0.1',
        user=pgrole,
        password=hash2.hex()
    )

    session['email'] = email
    session['organization'] = organization
    session['hash1'] = hash1.hex()

    return redirect(url_for('hello', name=hash2))

@app.route("/sprints")
@requires_login
def sprints(cursor):
    cursor.execute("SELECT * FROM jskplan.sprint")
    sprints = cursor.fetchall()
    return render_template('sprints.jinja2.html', sprints=sprints)

@app.route("/sprint/<int:sprint_id>")
@requires_login
def sprint(cursor, sprint_id):
    cursor.execute("SELECT * FROM jskplan.sprint WHERE sprint_id = %s", (sprint_id,))
    sprint = cursor.fetchone()
    print(sprint)

    cursor.execute("SELECT issue.* FROM jskplan.issue join jskplan.sprint_issue USING (issue_id) WHERE sprint_id = %s", (sprint_id,))
    issues = cursor.fetchall()
    return render_template('sprint.jinja2.html', sprint=sprint, issues=issues)

@app.route("/issue/<int:issue_id>")
@requires_login
def issue(cursor, issue_id):
    cursor.execute("SELECT * FROM jskplan.issue WHERE issue_id = %s", (issue_id,))
    issue = cursor.fetchone()

    cursor.execute("""
    WITH RECURSIVE parent_issues AS (
        SELECT 0 as n, *
        FROM jskplan.issue
        WHERE issue_id = %s

        UNION

        SELECT (parent_issues.n + 1) as n, issue.*
        FROM jskplan.issue
        JOIN parent_issues ON parent_issues.parent = issue.issue_id
    )
    SELECT *
    FROM parent_issues
    WHERE n > 0
    ORDER BY n DESC
    """, (issue_id,))
    parents = cursor.fetchall()

    cursor.execute("""
    WITH RECURSIVE child_issues AS (
        SELECT 1 as n, to_char(issue_id, '000000') as path, *
        FROM jskplan.issue
        WHERE parent = %s

        UNION

        SELECT (child_issues.n + 1) as n, child_issues.path || to_char(issue.issue_id, '000000') as path, issue.*
        FROM jskplan.issue
        JOIN child_issues ON child_issues.issue_id = issue.parent
    )
    SELECT *
    FROM child_issues
    ORDER BY path ASC
    """, (issue_id,))
    children = cursor.fetchall()

    print(children)

    cursor.execute("SELECT * FROM jskplan.note WHERE issue_id = %s", (issue_id,))
    notes = cursor.fetchall()

    return render_template('issue.jinja2.html', sprint=sprint, issue=issue, notes=notes, parents=parents, children=children)

@app.route("/<string:name>")
def hello(name):
    return render_template('hello.jinja2',name=name, count=session['count'])

if __name__ == "__main__":
    app.run()
