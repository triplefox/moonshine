typedef ParserConfig = {
	signature:String,
	version:String,
	formatVersion:Int,
	endianness:Bool,
	sizes: { size_t:Int, int:Int, number:Int, instruction:Int },
	integral : Int
};

typedef Local = {
	varname:String,
	startpc:Int,
	endpc:Int
};
	
typedef Chunk = {
	sourceName: String,
	lineDefined: Int,
	lastLineDefined: Int,
	upvalueCount: Int,
	paramCount: Int,
	is_vararg: Int,
	maxStackSize: Int,
	instructions: Array<Array<Int>>,
	constants: Array<Dynamic>,
	functions: Array<Chunk>,
	linePositions: Array<Int>,
	locals: Array<Local>,
	upvalues: Array<String>
};
	
class Parser {
	
	public static inline var LUA_TNIL = 0;
	public static inline var LUA_TBOOLEAN = 1;
	public static inline var LUA_TNUMBER = 3;
	public static inline var LUA_TSTRING = 4;

	public var data : String;
	public var pointer : Int;
	public var tree : Dynamic;
	public var runConfig : Dynamic;
	public var config : ParserConfig;
	
	public function readByte() {
		var r = data.charCodeAt(pointer) & 0xFF; pointer += 1; return r;
	}
	
	public function readBytes(?length : Int = -1) {
		if (length == -1) { var r = data.charCodeAt(pointer) & 0xFF; pointer += 1; return Std.string(r); }
		var r = data.substr(this.pointer, length); pointer += length; return r;
	}

	public function readString() {
	
		var byte = readBytes(config.sizes.size_t),
			length = 0,
			result,
			pos,
			i, l;

		if (config.endianness) {
			var i = config.sizes.size_t - 1;
			while (i >= 0) { length = length * 256 + byte.charCodeAt(i); i--; }
		} else {
			for (i in 0...config.sizes.size_t) { length = length * 256 + byte.charCodeAt(i); }
		}

		if (length<1) return '';

		result = readBytes(length);
		if (result.charCodeAt(length - 1) == 0) result = result.substr(0, length - 1);
//		pos = result.indexOf(String.fromCharCode(0));

//		if (pos >= 0) result = result.substr(0, pos);
		return result;
	}

	public function readInteger () {
		var b = readBytes(config.sizes.int),
			hex = '', char,
			i, l;
	
		for (i in 0...b.length) {
			char = ('0' + StringTools.hex(b.charCodeAt(i))).substr(-2);
			hex = this.config.endianness ? char + hex : hex + char;
		}

		return Std.parseInt(hex);
	}
	
	public function binaryStr(v : Int) {
		var result = "";
		while(v > 0) {
			result += Std.string(v & 1);
			v >> 1;
		}
		return result;
	}
	
	public function binStrInt(v : String) {
		var result = 0;
		for (i0 in 0...v.length) {
			result += ((v.charAt(i0) == "1") ? (1<<i0) : 0);
		}
		return result;
	}

	public function readNumber () {
 
        // Double precision floating-point format
        //    http://en.wikipedia.org/wiki/Double_precision_floating-point_format
        //    http://babbage.cs.qc.edu/IEEE-754/Decimal.html
 
        var number = this.readBytes(this.config.sizes.number),
            data = '';
     
        for (i in 0...number.length) {
            data = ('0000000' + binaryStr(number.charCodeAt(i))).substr(-8) + data;    // Beware: may need to be different for other endianess
        }
 
        var sign = binStrInt(data.substr( -64, 1));
        var exponent = binStrInt(data.substr( -63, 11));
        var mantissa = binFractionToDec(data.substr(-52, 52));
 
        if (exponent == 0) return 0.;
        if (exponent == 2047) return Math.POSITIVE_INFINITY;
 
        return Math.pow(-1, sign) * (1 + mantissa) * Math.pow(2, exponent - 1023);
    }
	
	public function binFractionToDec (mantissa) {
        var result = 0.;
     
        for (i in 0...mantissa.length) {
            if (mantissa.substr(i, 1) == '1') result += 1 / Math.pow(2, i + 1);
        }
 
        return result;
    };
	
	public function new () {
		data = null;
		pointer = null;
		tree = null;
	}
	
	public inline function readInstruction () {
		return readBytes(this.config.sizes.instruction);
	}

	public function readConstant () : Dynamic {
		var type = this.readByte();

		switch (type) {
			case LUA_TNIL: 		return null;
			case LUA_TBOOLEAN: 	return readByte() != 0;
			case LUA_TNUMBER: 	return readNumber();
			case LUA_TSTRING:	return readString();

			default: throw 'Unknown constant type: ' + type;
		}
	}

	public function readInstructionList () {
		var length = readInteger();
		return [for (i in 0...length) readInstruction()];
	}

	public function readConstantList () {
		var length = readInteger();
		return [for (i in 0...length) readConstant()];
	}

	public function readFunctionList () : Array<Chunk> {
		var length = readInteger();
		return [for (i in 0...length) readChunk()];
	}

	public function readStringList () {
		var length = readInteger();
		return [for (i in 0...length) readString()];
	}

	public function readIntegerList () {
		var length = readInteger();
		return [for (i in 0...length) readInteger()];
	}
	
	public function parseInstructions (instructions : Array<String>) : Array<Array<Int>> {
		return [ for (i in 0...instructions.length) parseInstruction(instructions[i]) ];
	};

	public function parseInstruction (instruction) : Array<Int> {
		var data = 0;
		var result = [0, 0, 0, 0];
		
		if (config.endianness) {
			var i = instruction.length;
			while (i >= 0) { data = (data << 8) + instruction.charCodeAt(i); i-=1; }
		} else {
			for (i in 0...instruction.length) data = (data << 8) + instruction.charCodeAt(i);
		}

		result[0] = data & 0x3f;
		result[1] = data >> 6 & 0xff;

		switch (result[0]) {
		
			// iABx
			case 1, //loadk
				 5, //getglobal
				 7, //setglobal
				 36: //closure
				result[2] = data >> 14 & 0x3fff;

			// iAsBx
			case 22, //jmp
				 31, //forloop
				 32: //forprep
				result[2] = (data >>> 14) - 0x1ffff;
					
			// iABC
			default:
				result[2] = data >> 23 & 0x1ff;
				result[3] = data >> 14 & 0x1ff;
		}
	
		return result;
	}

	public function readLocalsList () {
		var length = readInteger();
		return [for (i in 0...length) { 
				varname:readString(),
				startpc:readInteger(),
				endpc:readInteger()
				}];
	}
	
	public function readChunk () : Chunk {
	
		var result : Chunk = {
			sourceName: readString(),
			lineDefined: readInteger(),
			lastLineDefined: readInteger(),
			upvalueCount: readByte(),
			paramCount: readByte(),
			is_vararg: readByte(),
			maxStackSize: readByte(),
			instructions: parseInstructions(readInstructionList()),
			constants: readConstantList(),
			functions: readFunctionList(),
			linePositions: readIntegerList(),
			locals: readLocalsList(),
			upvalues: readStringList()
		};

		if (runConfig.stripDebugging) {
			result.linePositions = null;
			result.locals = null;
			result.upvalues = null;
		}
	
		return result;
	};

	/* --------------------------------------------------
	 * Parse input file
	 * -------------------------------------------------- */
	
	public function parse (filename : String, config : Dynamic, callback : Dynamic) {
		if (callback == null) {
			callback = config;
			config = {};
		}

		this.runConfig = config;
		if ( runConfig == null ) runConfig = { };
		
		var me = this,
			version,
			fs;
		
		if (filename.substr(0, 4) == [for ( i0 in [27, 76, 117, 97] ) String.fromCharCode(i0) ].join("") ) {
			// Lua byte code string
			version = Std.string(filename.charCodeAt(4));
			if (version != '51') throw 'The specified file was compiled with Lua v' + version.charAt(0) + '.' + version.charAt(1) + '; Moonshine can only parse bytecode created using the Lua v5.1 compiler.';

			parseData(filename);
			if (callback) callback(tree);

			return tree;
		}


		trace("// Load file");
		return null;
		//fs = require('fs');

		/*fs.readFile(filename, 'binary', function (err, data) {
			if (err) throw err;

			me._parseData('' + data);
			if (callback) callback(me._tree);
		});
		*/
	}

	public function parseData (data) {
		this.data = data;
		this.pointer = 0;

		this.readGlobalHeader();	
		this.tree = readChunk();

		this.runConfig = null;
	};

	public function getTree () {
		return this.tree;
	};

	public function readGlobalHeader () {

		var v = Std.string(readByte());
		this.config = {
			signature: readBytes(4),
			version: v.charAt(0) + '.' + v.charAt(1),
			formatVersion: readByte(),
			endianness: readByte() != 0,

			sizes: {
				int: readByte(),
				size_t: readByte(),
				instruction: readByte(),
				number: readByte(),
			},
		
			integral: readByte()
		};	
	};
	
}