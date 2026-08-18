"""AIOps node agent: a lightweight collector that runs on a real server and
forwards system metrics (and optionally a tailed log file) to a running
AIOps Incident Intelligence Platform API instance.

Deliberately separate from the ``aiops`` package (the server): this only
needs ``psutil`` and the standard library, so it can be deployed to a
plain node without pulling in FastAPI/SQLAlchemy/scikit-learn.
"""

__version__ = "1.0.0"
