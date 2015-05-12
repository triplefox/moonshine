import js.Browser;

class VM {
	
	private function resetGlobals() {}
	private function bindLib() {}
	public function load() {}
	public function execute() {}
	public function setGlobal() {}
	public function getGlobal() {}
	public function suspend() {}
	public function resume() {}
	public function dispose() {}
	public function getCurrentVM() {}
	
}

class MoonshineVM
{
	
    public static function inst() {
        
        var shine : Dynamic = null;
        untyped __js__(haxe.Resource.getString("everything.js"));
        
        // Standard output
        shine.stdout = {};

        shine.stdout.write = function (message) {
            // Overwrite this in host application
			trace(message);
        };

        // Standard debug output
        shine.stddebug = {};

        shine.stddebug.write = function (message) {
            // Moonshine bytecode debugging output
        };

        // Standard error output
        shine.stderr = {};

        shine.stderr.write = function (message, level) {
            level == null ? 'error' : level;
			if (Browser.window.console != null && Reflect.hasField(Browser.window.console, level)) 
				Reflect.field(Browser.window.console, level)(message);
        };        
        
        return shine;
        
    }

}