"""tempfile subset routed into the current explicitly owned build job."""
import tempfile as _tempfile
import build_workspace as workspace


def mkstemp(suffix=None, prefix=None, dir=None, text=False):
    return _tempfile.mkstemp(suffix=suffix, prefix=prefix, dir=workspace.temp_parent(dir), text=text)


def mkdtemp(suffix=None, prefix=None, dir=None):
    return _tempfile.mkdtemp(suffix=suffix, prefix=prefix, dir=workspace.temp_parent(dir))


def TemporaryDirectory(suffix=None, prefix=None, dir=None):
    return _tempfile.TemporaryDirectory(suffix=suffix, prefix=prefix, dir=workspace.temp_parent(dir))
