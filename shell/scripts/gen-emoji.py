#!/usr/bin/env python3
"""gen-emoji.py — builds qml/data/emoji.json for the search panel's emoji picker (":smile").

Source: Unicode's emoji-test.txt (package unicode-data on Debian / Ubuntu: /usr/share/unicode/emoji/emoji-test.txt, or pass a
path / URL). Only fully-qualified emoji without a skin tone are kept (~1900); the tones would triple the list for nothing a
picker needs. Keywords are the CLDR subgroup name plus a small alias table for the words people actually type ("lol",
"thumbs up", "fire"). Output is compact: [emoji, name, group index, extra keywords] per entry, ~120 KB.

Unicode data files are © Unicode, Inc., used under the Unicode License v3 (https://www.unicode.org/license.txt); the
notice travels in the JSON.
"""
import json, re, sys, urllib.request

SRC = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/unicode/emoji/emoji-test.txt"
OUT = sys.argv[2] if len(sys.argv) > 2 else "qml/data/emoji.json"

ALIASES = {  # emoji name (as in emoji-test.txt) -> words people type for it
    "grinning face": "smile happy", "grinning face with big eyes": "smile happy", "grinning face with smiling eyes": "smile happy",
    "beaming face with smiling eyes": "grin smile", "grinning squinting face": "laugh xd", "grinning face with sweat": "phew nervous",
    "rolling on the floor laughing": "rofl lol", "face with tears of joy": "lol joy laugh cry", "slightly smiling face": "smile",
    "upside-down face": "silly sarcasm", "winking face": "wink", "smiling face with smiling eyes": "blush happy",
    "smiling face with halo": "angel innocent", "smiling face with hearts": "love adore", "smiling face with heart-eyes": "love heart eyes",
    "star-struck": "wow stars", "face blowing a kiss": "kiss love", "face savoring food": "yum delicious", "face with tongue": "tongue silly",
    "winking face with tongue": "silly joke", "zany face": "crazy wild", "squinting face with tongue": "silly", "money-mouth face": "rich money",
    "smiling face with open hands": "hug", "face with hand over mouth": "oops giggle", "shushing face": "quiet shh secret",
    "thinking face": "hmm think", "zipper-mouth face": "silence secret", "face with raised eyebrow": "skeptical suspicious",
    "neutral face": "meh", "expressionless face": "meh blank", "face without mouth": "silent", "smirking face": "smirk flirt",
    "unamused face": "meh annoyed", "face with rolling eyes": "eye roll whatever", "grimacing face": "awkward", "lying face": "pinocchio liar",
    "relieved face": "relief", "pensive face": "sad thoughtful", "sleepy face": "tired", "drooling face": "drool", "sleeping face": "zzz sleep",
    "face with medical mask": "sick mask", "face with thermometer": "sick fever", "face with head-bandage": "hurt injured",
    "nauseated face": "sick green", "face vomiting": "puke sick", "sneezing face": "achoo sick", "hot face": "heat sweating",
    "cold face": "freezing", "woozy face": "drunk dizzy", "face with crossed-out eyes": "dead dizzy", "exploding head": "mind blown",
    "cowboy hat face": "yeehaw", "partying face": "party celebrate", "disguised face": "incognito", "smiling face with sunglasses": "cool",
    "nerd face": "geek glasses", "face with monocle": "fancy", "confused face": "confused", "worried face": "worried",
    "slightly frowning face": "sad", "frowning face": "sad", "face with open mouth": "surprised wow", "hushed face": "surprised",
    "astonished face": "shocked", "flushed face": "embarrassed blush", "pleading face": "puppy eyes please", "frowning face with open mouth": "shocked",
    "anguished face": "pain", "fearful face": "scared", "anxious face with sweat": "nervous", "sad but relieved face": "phew",
    "crying face": "sad tear", "loudly crying face": "sob bawl", "face screaming in fear": "scream horror", "confounded face": "frustrated",
    "persevering face": "struggle", "disappointed face": "sad", "downcast face with sweat": "tired", "weary face": "tired ugh",
    "tired face": "exhausted", "yawning face": "bored sleepy", "face with steam from nose": "angry triumph", "enraged face": "angry mad red",
    "angry face": "mad", "face with symbols on mouth": "swearing cursing", "smiling face with horns": "devil evil", "angry face with horns": "devil imp",
    "skull": "dead death", "skull and crossbones": "danger poison", "pile of poo": "poop shit", "clown face": "clown", "ogre": "monster",
    "goblin": "monster", "ghost": "boo halloween", "alien": "ufo", "alien monster": "space invader game", "robot": "bot",
    "grinning cat": "cat smile", "cat with tears of joy": "cat lol", "red heart": "love", "orange heart": "love", "yellow heart": "love",
    "green heart": "love", "blue heart": "love", "purple heart": "love", "black heart": "love", "white heart": "love", "brown heart": "love",
    "broken heart": "heartbreak sad", "sparkling heart": "love", "growing heart": "love", "beating heart": "love", "revolving hearts": "love",
    "two hearts": "love", "heart with arrow": "cupid love", "heart with ribbon": "gift love", "heart exclamation": "love", "kiss mark": "lips",
    "hundred points": "100 perfect score", "anger symbol": "angry", "collision": "boom bang", "dizzy": "stars", "sweat droplets": "water",
    "dashing away": "fast wind", "hole": "hole", "speech balloon": "chat talk", "thought balloon": "thinking", "zzz": "sleep",
    "waving hand": "hi bye hello wave", "raised back of hand": "hand", "hand with fingers splayed": "hand five", "raised hand": "stop high five",
    "vulcan salute": "spock star trek", "ok hand": "okay perfect", "pinched fingers": "italian", "pinching hand": "small tiny",
    "victory hand": "peace two", "crossed fingers": "luck hope", "love-you gesture": "ily", "sign of the horns": "rock metal",
    "call me hand": "shaka", "backhand index pointing left": "point left", "backhand index pointing right": "point right",
    "backhand index pointing up": "point up", "middle finger": "rude", "backhand index pointing down": "point down",
    "index pointing up": "point up one", "thumbs up": "like yes ok +1 good", "thumbs down": "dislike no -1 bad", "raised fist": "power solidarity",
    "oncoming fist": "punch bro fist bump", "left-facing fist": "punch", "right-facing fist": "punch", "clapping hands": "applause bravo clap",
    "raising hands": "hooray praise celebrate", "open hands": "hug", "palms up together": "pray", "handshake": "deal agreement",
    "folded hands": "pray please thanks", "writing hand": "write", "nail polish": "nails sassy", "selfie": "photo", "flexed biceps": "strong muscle gym",
    "eyes": "look see", "eye": "see", "brain": "smart", "person shrugging": "shrug dunno idk", "person facepalming": "facepalm",
    "man shrugging": "shrug", "woman shrugging": "shrug", "man facepalming": "facepalm", "woman facepalming": "facepalm",
    "dog face": "puppy", "cat face": "kitty", "fire": "hot lit flame", "sparkles": "shiny magic", "star": "favourite", "glowing star": "shiny",
    "sun": "sunny weather", "cloud": "weather", "cloud with rain": "rain weather", "snowflake": "snow cold winter", "high voltage": "lightning zap electric",
    "rainbow": "pride", "party popper": "tada celebrate congratulations", "confetti ball": "celebrate", "balloon": "party birthday",
    "wrapped gift": "present birthday", "birthday cake": "cake", "trophy": "win winner award", "1st place medal": "gold winner first",
    "sports medal": "award", "direct hit": "target bullseye", "video game": "controller gaming", "joystick": "gaming", "rocket": "launch ship space",
    "bug": "insect", "lady beetle": "ladybug", "check mark button": "done yes ok tick", "check mark": "done yes tick", "cross mark": "no wrong x",
    "warning": "caution", "prohibited": "no forbidden", "red question mark": "question", "red exclamation mark": "exclamation important",
    "double exclamation mark": "important", "hot beverage": "coffee tea cup", "beer mug": "beer drink", "clinking beer mugs": "cheers beer",
    "clinking glasses": "cheers toast champagne", "wine glass": "wine drink", "pizza": "food", "hamburger": "burger food", "french fries": "fries",
    "taco": "food", "sushi": "food japan", "eyes on the road": "", "light bulb": "idea", "laptop": "computer", "desktop computer": "pc",
    "keyboard": "typing", "computer mouse": "mouse", "floppy disk": "save", "gear": "settings cog", "wrench": "tool fix", "hammer": "tool",
    "hammer and wrench": "tools fix", "locked": "lock secure", "unlocked": "open lock", "key": "password", "magnifying glass tilted left": "search zoom",
    "magnifying glass tilted right": "search zoom", "bell": "notification", "bell with slash": "mute silent", "megaphone": "announce", "loudspeaker": "announce",
    "musical note": "music", "musical notes": "music song", "headphone": "music", "microphone": "sing", "camera": "photo", "movie camera": "film video",
    "television": "tv", "money bag": "cash rich", "dollar banknote": "money cash", "credit card": "pay", "chart increasing": "up growth stocks",
    "chart decreasing": "down loss stocks", "bar chart": "stats", "calendar": "date", "alarm clock": "time wake", "hourglass done": "time wait",
    "stopwatch": "timer", "pushpin": "pin location", "round pushpin": "pin location", "paperclip": "attach", "memo": "note write pencil",
    "pencil": "write", "books": "read study", "open book": "read", "envelope": "mail email letter", "e-mail": "email", "incoming envelope": "mail",
    "package": "box delivery", "link": "url chain", "globe with meridians": "www internet web", "house": "home", "office building": "work",
    "airplane": "flight travel", "automobile": "car", "bicycle": "bike", "bus": "transport", "train": "transport", "police car light": "siren alert",
    "no entry": "stop", "stop sign": "stop", "recycling symbol": "recycle", "white heavy check mark": "done", "shopping cart": "buy",
    "sleeping face on bed": "", "smiling face with tear": "grateful", "melting face": "hot dissolve", "face with open eyes and hand over mouth": "gasp",
    "face with peeking eye": "peek", "saluting face": "salute yes sir", "dotted line face": "invisible", "face holding back tears": "touched",
    "face with diagonal mouth": "meh unsure", "shaking face": "shook vibrate", "heart on fire": "passion", "mending heart": "healing",
    "salute": "", "person raising hand": "question volunteer", "person tipping hand": "sassy", "detective": "spy", "ninja": "stealth",
    "man technologist": "developer coder programmer", "woman technologist": "developer coder programmer", "technologist": "developer coder programmer",
    "snake": "python", "crab": "rust", "gem stone": "ruby diamond", "elephant": "postgres", "penguin": "linux tux", "spouting whale": "docker",
    "butterfly": "", "unicorn": "magic", "t-rex": "dinosaur", "turtle": "slow", "sloth": "slow lazy", "monkey": "", "see-no-evil monkey": "monkey hide",
    "hear-no-evil monkey": "monkey", "speak-no-evil monkey": "monkey oops", "zombie": "", "eggplant": "aubergine", "peach": "butt",
    "avocado": "", "hot pepper": "spicy chili", "cookie": "biscuit", "doughnut": "donut", "popcorn": "movie", "cheese wedge": "cheese",
    "bacon": "", "egg": "", "cooking": "fried egg", "bread": "toast", "croissant": "", "waffle": "", "pancakes": "", "chocolate bar": "candy",
    "candy": "sweet", "lollipop": "sweet", "ice cream": "dessert", "shaved ice": "dessert", "soft ice cream": "dessert", "cupcake": "dessert",
    "pie": "", "watermelon": "", "banana": "", "strawberry": "", "cherries": "", "grapes": "", "lemon": "sour", "red apple": "apple fruit",
    "tomato": "", "broccoli": "vegetable", "carrot": "vegetable", "corn": "maize", "potato": "", "mushroom": "", "garlic": "", "onion": "",
    "rose": "flower romance", "tulip": "flower", "sunflower": "flower", "cherry blossom": "flower sakura", "hibiscus": "flower", "bouquet": "flowers",
    "four leaf clover": "luck lucky", "seedling": "plant sprout", "herb": "plant", "evergreen tree": "christmas pine", "deciduous tree": "tree",
    "palm tree": "beach holiday", "cactus": "desert", "maple leaf": "autumn canada", "fallen leaf": "autumn", "leaf fluttering in wind": "leaf",
    "crescent moon": "night", "full moon": "night", "new moon face": "moon", "shooting star": "wish", "milky way": "space galaxy", "comet": "space",
    "earth globe europe-africa": "world planet", "earth globe americas": "world planet", "earth globe asia-australia": "world planet",
    "umbrella with rain drops": "rain", "cyclone": "hurricane spiral", "fog": "mist", "wind face": "blowing", "droplet": "water",
    "water wave": "ocean surf", "tornado": "storm", "cloud with lightning and rain": "storm thunder", "sun behind cloud": "partly cloudy",
    "sun behind rain cloud": "showers", "thermometer": "temperature", "snowman": "winter", "christmas tree": "xmas holiday", "jack-o-lantern": "halloween pumpkin",
    "fireworks": "celebrate new year", "sparkler": "celebrate", "hugging face": "hug", "face exhaling": "sigh", "face in clouds": "foggy absent",
    "face with spiral eyes": "hypnotised dizzy", "smiling face": "relaxed", "kissing face": "kiss", "kissing face with closed eyes": "kiss",
    "kissing face with smiling eyes": "kiss", "kissing face with closed eyes and smiling": "", "beaming face with open mouth": "", "smiling cat with heart-eyes": "cat love",
    "weary cat": "cat", "crying cat": "cat sad", "pouting cat": "cat angry", "poodle": "dog", "guide dog": "dog", "service dog": "dog", "dog": "puppy",
    "wolf": "", "fox": "", "raccoon": "", "cat": "kitty", "black cat": "halloween", "lion": "", "tiger face": "tiger", "horse face": "horse", "cow face": "cow",
    "pig face": "pig", "pig nose": "pig", "frog": "", "bear": "", "panda": "", "koala": "", "hamster": "", "rabbit face": "bunny", "mouse face": "mouse",
    "hatching chick": "chick", "baby chick": "chick", "chicken": "", "bird": "", "eagle": "", "duck": "", "owl": "", "bat": "halloween", "shark": "", "octopus": "",
    "dolphin": "", "fish": "", "tropical fish": "fish", "blowfish": "fish", "honeybee": "bee", "ant": "", "spider": "halloween", "scorpion": "", "dragon": "",
    "dragon face": "dragon", "sauropod": "dinosaur", "shrimp": "", "lobster": "", "squid": "", "oyster": "", "bone": "", "tooth": "dentist",
    "ear": "listen", "nose": "smell", "mouth": "lips", "tongue": "", "foot": "", "leg": "", "mechanical arm": "robot", "mechanical leg": "robot",
    "baby": "", "child": "kid", "boy": "", "girl": "", "person": "", "man": "", "woman": "", "older person": "old", "old man": "grandpa", "old woman": "grandma",
    "health worker": "doctor nurse", "student": "graduate", "teacher": "school", "judge": "law", "farmer": "", "cook": "chef", "mechanic": "",
    "factory worker": "", "office worker": "business", "scientist": "lab", "singer": "music", "artist": "paint", "pilot": "plane", "astronaut": "space",
    "firefighter": "fire", "police officer": "cop", "guard": "", "construction worker": "", "prince": "", "princess": "", "superhero": "", "supervillain": "",
    "mage": "wizard", "fairy": "", "vampire": "halloween", "merperson": "mermaid", "elf": "", "genie": "", "person getting massage": "spa",
    "person getting haircut": "barber", "person walking": "walk", "person running": "run jog", "person dancing": "dance", "man dancing": "dance",
    "person in suit levitating": "", "people with bunny ears": "party", "person in steamy room": "sauna", "person climbing": "climb", "person fencing": "",
    "horse racing": "", "skier": "ski", "snowboarder": "", "person golfing": "golf", "person surfing": "surf", "person rowing boat": "row",
    "person swimming": "swim", "person bouncing ball": "basketball", "person lifting weights": "gym workout", "person biking": "cycling",
    "person mountain biking": "cycling", "person cartwheeling": "", "people wrestling": "", "person playing water polo": "", "person playing handball": "",
    "person juggling": "", "person in lotus position": "yoga meditate", "person taking bath": "bath", "person in bed": "sleep",
    "couple with heart": "love", "kiss": "love", "family": "", "speaking head": "talk", "bust in silhouette": "user profile", "busts in silhouette": "users group",
    "people hugging": "hug", "footprints": "", "soccer ball": "football", "basketball": "", "american football": "", "tennis": "", "volleyball": "",
    "baseball": "", "rugby football": "rugby", "flying disc": "frisbee", "bowling": "", "cricket game": "cricket", "field hockey": "hockey", "ice hockey": "hockey",
    "ping pong": "table tennis", "badminton": "", "boxing glove": "boxing", "martial arts uniform": "karate", "goal net": "goal", "flag in hole": "golf",
    "ice skate": "skating", "fishing pole": "fishing", "diving mask": "dive", "running shirt": "", "skis": "ski", "sled": "", "curling stone": "",
    "bullseye": "target", "yo-yo": "", "kite": "", "pool 8 ball": "billiards", "crystal ball": "fortune", "magic wand": "magic", "nazar amulet": "evil eye",
    "slot machine": "casino", "game die": "dice", "puzzle piece": "jigsaw", "teddy bear": "", "pinata": "", "mirror ball": "disco", "nesting dolls": "",
    "spade suit": "cards", "heart suit": "cards", "diamond suit": "cards", "club suit": "cards", "chess pawn": "chess", "joker": "cards", "mahjong red dragon": "",
    "flower playing cards": "", "performing arts": "theatre masks", "framed picture": "art", "artist palette": "art paint", "thread": "sewing", "yarn": "knitting",
    "sewing needle": "", "knot": "", "glasses": "", "sunglasses": "cool", "goggles": "", "lab coat": "", "safety vest": "", "necktie": "tie", "t-shirt": "shirt",
    "jeans": "", "scarf": "", "gloves": "", "coat": "", "socks": "", "dress": "", "kimono": "", "sari": "", "bikini": "", "shorts": "", "purse": "", "handbag": "",
    "backpack": "", "thong sandal": "", "running shoe": "sneaker", "hiking boot": "", "flat shoe": "", "high-heeled shoe": "heels", "crown": "king queen",
    "top hat": "", "graduation cap": "graduate", "billed cap": "cap", "military helmet": "", "rescue worker's helmet": "", "prayer beads": "", "lipstick": "",
    "ring": "engaged wedding", "briefcase": "work", "bomb": "explode", "hourglass not done": "time wait", "watch": "time", "mantelpiece clock": "time",
    "timer clock": "", "telescope": "space", "microscope": "science", "satellite antenna": "signal", "syringe": "vaccine shot", "pill": "medicine",
    "stethoscope": "doctor", "adhesive bandage": "band-aid", "crutch": "", "x-ray": "", "door": "", "elevator": "", "window": "", "bed": "sleep", "couch and lamp": "sofa",
    "chair": "", "toilet": "", "shower": "", "bathtub": "bath", "razor": "", "lotion bottle": "", "safety pin": "", "broom": "clean", "basket": "", "roll of paper": "",
    "bucket": "", "soap": "wash", "sponge": "clean", "fire extinguisher": "", "toothbrush": "", "mobile phone": "phone cell", "mobile phone with arrow": "phone",
    "telephone": "phone", "telephone receiver": "phone call", "pager": "", "fax machine": "fax", "battery": "power", "low battery": "power",
    "electric plug": "power", "printer": "print", "computer disk": "", "optical disk": "cd dvd", "dvd": "", "abacus": "", "film projector": "movie",
    "clapper board": "movie action", "radio": "", "studio microphone": "podcast", "level slider": "", "control knobs": "", "compass": "", "bricks": "wall",
    "rock": "stone", "wood": "log", "hut": "", "fuel pump": "gas petrol", "wheel": "", "nut and bolt": "", "screwdriver": "tool", "axe": "", "pick": "mining",
    "chains": "", "hook": "", "toolbox": "tools", "magnet": "", "ladder": "", "test tube": "science", "petri dish": "science", "dna": "genetics",
    "satellite": "space", "flying saucer": "ufo", "trolleybus": "", "minibus": "van", "ambulance": "emergency", "fire engine": "firetruck", "police car": "cops",
    "taxi": "cab", "sport utility vehicle": "suv car", "pickup truck": "", "delivery truck": "", "tractor": "", "racing car": "fast f1", "motorcycle": "bike",
    "motor scooter": "", "manual wheelchair": "", "motorized wheelchair": "", "auto rickshaw": "", "kick scooter": "", "skateboard": "", "roller skate": "",
    "bus stop": "", "motorway": "highway road", "railway track": "train", "oil drum": "", "anchor": "", "sailboat": "boat", "canoe": "", "speedboat": "boat",
    "passenger ship": "cruise", "ferry": "", "motor boat": "", "ship": "boat", "small airplane": "plane", "airplane departure": "takeoff", "airplane arrival": "landing",
    "parachute": "", "seat": "", "helicopter": "", "suspension railway": "", "mountain cableway": "", "aerial tramway": "", "luggage": "suitcase travel",
    "world map": "map", "compass rose": "", "snow-capped mountain": "mountain", "mountain": "", "volcano": "", "mount fuji": "japan", "camping": "tent",
    "beach with umbrella": "beach holiday", "desert": "", "desert island": "island", "national park": "", "stadium": "", "classical building": "",
    "building construction": "", "brick": "", "houses": "", "derelict house": "", "house with garden": "home", "post office": "", "hospital": "",
    "bank": "", "hotel": "", "love hotel": "", "convenience store": "", "school": "", "department store": "", "factory": "", "castle": "", "wedding": "",
    "tokyo tower": "japan", "statue of liberty": "new york", "church": "", "mosque": "", "synagogue": "", "hindu temple": "", "kaaba": "", "shinto shrine": "",
    "fountain": "", "tent": "camping", "foggy": "", "night with stars": "night", "cityscape": "city", "sunrise over mountains": "sunrise", "sunrise": "morning",
    "cityscape at dusk": "sunset", "sunset": "", "bridge at night": "", "hot springs": "onsen", "carousel horse": "", "playground slide": "", "ferris wheel": "",
    "roller coaster": "", "barber pole": "", "circus tent": "", "locomotive": "train", "railway car": "train", "high-speed train": "bullet train shinkansen",
    "bullet train": "train", "metro": "subway", "light rail": "tram", "station": "train", "tram": "", "monorail": "", "mountain railway": "", "tram car": "",
    "atm sign": "cash", "litter in bin sign": "trash", "potable water": "", "wheelchair symbol": "accessible", "men's room": "toilet", "women's room": "toilet",
    "restroom": "toilet", "baby symbol": "", "water closet": "toilet", "passport control": "", "customs": "", "baggage claim": "", "left luggage": "",
    "children crossing": "", "no bicycles": "", "no smoking": "", "no littering": "", "non-potable water": "", "no pedestrians": "", "no mobile phones": "",
    "no one under eighteen": "18+", "radioactive": "nuclear", "biohazard": "", "up arrow": "north", "up-right arrow": "", "right arrow": "east next",
    "down-right arrow": "", "down arrow": "south", "down-left arrow": "", "left arrow": "west back", "up-left arrow": "", "up-down arrow": "", "left-right arrow": "",
    "right arrow curving left": "back return", "left arrow curving right": "forward", "right arrow curving up": "", "right arrow curving down": "",
    "clockwise vertical arrows": "refresh", "counterclockwise arrows button": "refresh sync", "back arrow": "", "end arrow": "", "on! arrow": "", "soon arrow": "",
    "top arrow": "", "place of worship": "", "atom symbol": "science", "om": "", "star of david": "", "wheel of dharma": "", "yin yang": "balance", "latin cross": "",
    "orthodox cross": "", "star and crescent": "", "peace symbol": "peace", "menorah": "", "dotted six-pointed star": "", "aries": "zodiac", "taurus": "zodiac",
    "gemini": "zodiac", "cancer": "zodiac", "leo": "zodiac", "virgo": "zodiac", "libra": "zodiac", "scorpio": "zodiac", "sagittarius": "zodiac", "capricorn": "zodiac",
    "aquarius": "zodiac", "pisces": "zodiac", "ophiuchus": "zodiac", "shuffle tracks button": "shuffle random", "repeat button": "loop", "repeat single button": "loop",
    "play button": "play", "fast-forward button": "forward", "next track button": "skip next", "play or pause button": "play pause", "reverse button": "rewind",
    "fast reverse button": "rewind", "last track button": "previous", "upwards button": "up", "fast up button": "", "downwards button": "down", "fast down button": "",
    "pause button": "pause", "stop button": "stop", "record button": "record", "eject button": "", "cinema": "movie", "dim button": "brightness", "bright button": "brightness",
    "antenna bars": "signal wifi", "wireless": "wifi", "vibration mode": "", "mobile phone off": "", "female sign": "", "male sign": "", "transgender symbol": "",
    "multiply": "x times", "plus": "add", "minus": "subtract", "divide": "", "heavy equals sign": "equals", "infinity": "forever", "double curly loop": "",
    "curly loop": "", "part alternation mark": "", "eight-spoked asterisk": "", "eight-pointed star": "", "sparkle": "", "trade mark": "tm", "copyright": "",
    "registered": "", "keycap: #": "hash", "keycap: *": "asterisk star", "keycap: 0": "zero", "keycap: 1": "one", "keycap: 2": "two", "keycap: 3": "three",
    "keycap: 4": "four", "keycap: 5": "five", "keycap: 6": "six", "keycap: 7": "seven", "keycap: 8": "eight", "keycap: 9": "nine", "keycap: 10": "ten",
    "input latin uppercase": "abc", "input latin lowercase": "abc", "input numbers": "123", "input symbols": "", "input latin letters": "abc",
    "a button (blood type)": "a", "ab button (blood type)": "ab", "b button (blood type)": "b", "cl button": "", "cool button": "cool", "free button": "free",
    "information": "info", "id button": "id", "circled m": "metro", "new button": "new", "ng button": "", "o button (blood type)": "o", "ok button": "ok",
    "p button": "parking", "sos button": "help emergency", "up! button": "", "vs button": "versus", "red circle": "circle", "orange circle": "circle",
    "yellow circle": "circle", "green circle": "circle", "blue circle": "circle", "purple circle": "circle", "brown circle": "circle", "black circle": "circle",
    "white circle": "circle", "red square": "square", "orange square": "square", "yellow square": "square", "green square": "square", "blue square": "square",
    "purple square": "square", "brown square": "square", "black large square": "square", "white large square": "square", "black medium square": "square",
    "white medium square": "square", "black medium-small square": "square", "white medium-small square": "square", "black small square": "square",
    "white small square": "square", "large orange diamond": "diamond", "large blue diamond": "diamond", "small orange diamond": "diamond", "small blue diamond": "diamond",
    "red triangle pointed up": "triangle", "red triangle pointed down": "triangle", "diamond with a dot": "", "radio button": "", "white square button": "",
    "black square button": "", "chequered flag": "finish race done", "triangular flag": "flag", "crossed flags": "japan", "black flag": "", "white flag": "surrender",
    "rainbow flag": "pride lgbt", "transgender flag": "pride", "pirate flag": "pirate", "eyes on": "", "keycap": "",
}

def main():
    if SRC.startswith("http"):
        text = urllib.request.urlopen(SRC).read().decode("utf-8")
    else:
        text = open(SRC, encoding="utf-8").read()
    groups, entries = [], []
    group = subgroup = None
    line_re = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E\d+\.\d+\s+(.*)$")
    for line in text.splitlines():
        if line.startswith("# group: "):
            group = line[9:].strip(); groups.append(group); continue
        if line.startswith("# subgroup: "):
            subgroup = line[12:].strip(); continue
        m = line_re.match(line)
        if not m or "skin tone" in m.group(3):
            continue
        cps, glyph, name = m.group(1), m.group(2), m.group(3)
        # the glyph column IS the emoji, but rebuild it from the code points so a mangled copy of the file cannot bite
        emoji = "".join(chr(int(c, 16)) for c in cps.split())
        words = subgroup.replace("-", " ").replace("&", "").split() if subgroup else []
        extra = ALIASES.get(name, "")
        # keep only words the name does not already contain
        low = name.lower()
        kw = " ".join(dict.fromkeys(w for w in (words + extra.split()) if w and w.lower() not in low))
        row = [emoji, name, groups.index(group)]
        if kw:
            row.append(kw)
        entries.append(row)
    out = {
        "license": "Emoji names and ordering from Unicode emoji-test.txt, © Unicode, Inc. Used under the Unicode License v3 (https://www.unicode.org/license.txt). Keyword aliases: Sirca Shell, GPL-3.0-or-later.",
        "version": next((l.split(":", 1)[1].strip() for l in text.splitlines() if l.startswith("# Version:")), ""),
        "groups": groups,
        "emoji": entries,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(f"{len(entries)} emoji in {len(groups)} groups -> {OUT}")

if __name__ == "__main__":
    main()
