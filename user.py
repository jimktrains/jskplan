from functools import wraps
from flask import session, url_for, redirect, flash
import hashlib
import json
from config import config
import logging
import psycopg2
import psycopg2.extras

def dbrole(user, organization):
    return user + "@" + organization

def password_hash1(user, organization, password):
    salt = hashlib.sha512(json.dumps({"user": user, "organization": organization, "salt": config['auth']['hash1_key']}).encode('utf8')).digest()
    pwd = hashlib.scrypt(password.encode('utf8'), salt=salt, n=16, r=10, p=10)
    return pwd

def password_hash2(user, organization, hash1):
    salt = hashlib.sha512(json.dumps({"user": user, "organization": organization, "hash1": hash1.hex()}).encode('utf8')).digest()
    pwd = hashlib.scrypt(hash1, salt=salt, n=16, r=10, p=10)
    return pwd

def requires_login(f):
    @wraps(f)
    def inside(**kwargs):
        if 'email' in session and \
           'organization' in session and \
           'hash1' in session:

            conn, pgrole = login(session['email'], session['organization'], bytes.fromhex(session['hash1']))
            if conn is not None:
                with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cursor:
                    return f(cursor, pgrole, **kwargs)
        return redirect(url_for('login'))
    return inside

def login(email, organization, hash1):
    hash2 = password_hash2(email, organization, hash1)
    pgrole = dbrole(email, organization)
    try:
        conn = psycopg2.connect(
            dbname=config['db']['dbname'],
            host=config['db']['host'],
            user=pgrole,
            password=hash2.hex()
        )
        conn.autocommit = True
        return conn, (pgrole, organization)
    except Exception as e:
        logging.error(str(e), exc_info=1)
        flash('Login failed')
        return None, None

