Reserved keys
=============

Sib trace format. Follows `Open Responses
<https://www.openresponses.org/specification>`__ item fields except
``sib:`` prefixed keys (for metadata).

+-----------------------+----------------------------------------------+
| key                   | meaning                                      |
+=======================+==============================================+
| ``type``              | ``message`` (default), ``function_call``,    |
|                       | ``function_call_output``, ``reasoning``      |
+-----------------------+----------------------------------------------+
| ``content``           | Payload: message text, call arguments, call  |
|                       | output                                       |
+-----------------------+----------------------------------------------+
| ``summary``           | ``reasoning``. Summary texts joined by blank |
|                       | lines                                        |
+-----------------------+----------------------------------------------+
| ``role``              | ``message`` only. ``user``, ``assistant``,   |
|                       | ``system``, ``developer``                    |
+-----------------------+----------------------------------------------+
| ``call_id``           | ``function_call``, ``function_call_output``. |
|                       | Pairs a call with its output                 |
+-----------------------+----------------------------------------------+
| ``name``              | ``function_call``. Function name             |
+-----------------------+----------------------------------------------+
| ``encrypted_content`` | ``reasoning``. Opaque, passed back as is     |
+-----------------------+----------------------------------------------+
| ``status``            | Present only when not ``completed``          |
+-----------------------+----------------------------------------------+

Minimum rules for compatibility
-------------------------------

- Keys must match ``[A-Za-z_][A-Za-z0-9._:-]*``.
- ``type`` defaults to ``message``; the other reserved keys depend on it.
- The commit date is fixed at ``999999999 +0000``, with author and
  committer ``Sibyl <sib@local>``. Through this, we can obtain the same
  hash for the same conversation chain.
