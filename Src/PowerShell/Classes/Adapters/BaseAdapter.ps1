
class BaseAdapter {
    [string]$Name

    BaseAdapter([string]$name) {
        $this.Name = $name
    }

    [void] Start([Conduit]$conduit) {
        throw "Start() must be implemented by Adapter subclass."
    }

    [void] Stop() {
        throw "Stop() must be implemented by Adapter subclass."
    }
}
