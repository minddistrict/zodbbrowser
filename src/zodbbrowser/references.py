
import sqlite3

from ZODB.utils import u64
from ZODB.serialize import referencesf
from zope.interface import implements

from zodbbrowser.interfaces import IReferencesDatabase


def connect(callback):
    """Decorator for the reference database to access the sqlite DB."""

    def wrapper(self, *args, **kwargs):
        try:
            connection = sqlite3.connect(self.db_name)
        except:
            raise ValueError(
                'impossible to open references database {}.'.format(
                    self.db_name))
        try:
            result = callback(self, connection, *args, **kwargs)
        finally:
            connection.close()
        return result

    return wrapper


class ReferencesDatabase(object):
    implements(IReferencesDatabase)

    def __init__(self, db_name):
        self.db_name = db_name

    @connect
    def analyzeRecords(self, connection, records):
        cursor = connection.cursor()
        for record in records:
            current_oid = u64(record.oid)
            referred_oids = set(map(u64, referencesf(record.data)))

            for referred_oid in referred_oids or [-1]:
                cursor.execute("""
INSERT INTO links (source_oid, target_oid) VALUES
(?, ?)
            """, (current_oid, referred_oid))
        connection.commit()

    @connect
    def createDatabase(self, connection):
        cursor = connection.cursor()
        cursor.execute("""
CREATE TABLE IF NOT EXISTS links
(source_oid BIGINT, target_oid BIGINT)
        """)
        cursor.execute("""
CREATE INDEX IF NOT EXISTS source_oid_index ON links (source_oid)
        """)
        cursor.execute("""
CREATE INDEX IF NOT EXISTS target_oid_index ON links (target_oid)
        """)
        connection.commit()

    @connect
    def checkDatabase(self, connection):
        cursor = connection.cursor()
        try:
            result = cursor.execute("SELECT count(*) FROM links")
            result.fetchall()
        except sqlite3.OperationalError:
            return False
        return True

    @connect
    def getUnUsedOIDs(self, connection):
        oids = set([])
        cursor = connection.cursor()
        result = cursor.execute("""
WITH RECURSIVE links_to_root (source_oid, target_oid) AS (
    SELECT source_oid, target_oid
    FROM links
    WHERE source_oid = 0
    UNION
    SELECT linked.source_oid, linked.target_oid
    FROM links AS linked JOIN links_to_root AS origin
        ON origin.target_oid = linked.source_oid
    ORDER BY linked.source_oid
)
SELECT DISTINCT source_oid FROM links
EXCEPT SELECT DISTINCT source_oid FROM links_to_root
        """)
        for oid in result.fetchall():
            oids.add(oid[0])
        return oids

    @connect
    def linkedToOID(self, connection, oid, depth):
        cursor = connection.cursor()
        result = cursor.execute("""
WITH RECURSIVE linked_to_oid (source_oid, depth) AS (
    SELECT source_oid, 1
    FROM links
    WHERE target_oid = ?
    UNION
    SELECT link.source_oid, target.depth + 1
    FROM links AS link JOIN linked_to_oid AS target
        ON target.source_oid = link.target_oid
    WHERE target.depth < ?
    ORDER BY link.source_oid
)
SELECT DISTINCT source_oid, depth FROM linked_to_oid WHERE depth = ?
        """, (oid, depth, depth))
        linked = []
        for line in result.fetchall():
            linked.append((line[0], line[1]))
        return linked

    @connect
    def getMissingOIDs(self, connection):
        oids = set([])
        cursor = connection.cursor()
        result = cursor.execute("""
SELECT a.target_oid FROM links AS a LEFT OUTER JOIN links AS b
ON a.target_oid = b.source_oid
WHERE a.target_oid > -1 AND b.source_oid IS NULL
        """)
        for oid in result.fetchall():
            oids.add(oid[0])
        return oids

    @connect
    def getForwardReferences(self, connection, oid):
        oids = set([])
        cursor = connection.cursor()
        result = cursor.execute("""
SELECT target_oid FROM links
WHERE source_oid = ? AND target_oid > -1
        """, (u64(oid), ))
        for oid in result.fetchall():
            oids.add(oid[0])
        return oids

    @connect
    def getBackwardReferences(self, connection, oid):
        oids = set([])
        cursor = connection.cursor()
        result = cursor.execute("""
SELECT source_oid FROM links
WHERE target_oid = ?
        """, (u64(oid), ))
        for oid in result.fetchall():
            oids.add(oid[0])
        return oids
