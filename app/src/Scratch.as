/*
 * Scratch Project Editor and Player
 * Copyright (C) 2014 Massachusetts Institute of Technology
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

// Scratch.as
// John Maloney, September 2009
//
// This is the top-level application.

package {


import blocks.Block;

import connectors.*;

import extensions.ExtensionManager;

import flash.display.DisplayObject;
import flash.display.Graphics;
import flash.display.Shape;
import flash.display.Sprite;
import flash.display.StageAlign;
import flash.display.StageDisplayState;
import flash.display.StageScaleMode;
import flash.errors.IllegalOperationError;
import flash.events.ErrorEvent;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.events.TextEvent;
import flash.events.UncaughtErrorEvent;
TARGET::android {
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
}
import flash.geom.Point;
import flash.geom.Rectangle;
import flash.net.FileReference;
import flash.net.FileReferenceList;
import flash.net.LocalConnection;
import flash.net.URLRequest;
import flash.net.navigateToURL;
import flash.system.Capabilities;
import flash.system.System;
import flash.text.*;
import flash.utils.ByteArray;
import flash.utils.getTimer;

import interpreter.Interpreter;

import render3d.DisplayObjectContainerIn3D;

import scratch.BlockMenus;
import scratch.PaletteBuilder;
import scratch.ScratchCostume;
import scratch.ScratchObj;
import scratch.ScratchRuntime;
import scratch.ScratchSound;
import scratch.ScratchSprite;
import scratch.ScratchStage;

import translation.Translator;

import ui.BlockPalette;
import ui.CameraDialog;
import ui.LoadProgress;
import ui.media.MediaInfo;
import ui.media.MediaLibrary;
import ui.media.MediaPane;
import ui.parts.ImagesPart;
import ui.parts.LibraryPart;
import ui.parts.ScratchBoardPart;
import ui.parts.ScriptsPart;
import ui.parts.SoundsPart;
import ui.parts.StagePart;
import ui.parts.TabsPart;
import ui.parts.TopBarPart;

import uiwidgets.BlockColorEditor;
import uiwidgets.CursorTool;
import uiwidgets.DialogBox;
import uiwidgets.IconButton;
import uiwidgets.Menu;
import uiwidgets.ScriptsPane;

import util.GestureHandler;
import util.ProjectIO;
import util.Server;
import util.StringUtils;
import util.Transition;
import util.UnimplementedError;

import watchers.ListWatcher;

TARGET::android {
    import com.as3breeze.air.ane.android.events.BluetoothDeviceEvent;
	import pl.mateuszmackowiak.nativeANE.dialogs.NativeAlertDialog;
	import pl.mateuszmackowiak.nativeANE.dialogs.NativeListDialog;
	import pl.mateuszmackowiak.nativeANE.dialogs.NativeProgressDialog;
	import pl.mateuszmackowiak.nativeANE.dialogs.NativeTextInputDialog;
	import pl.mateuszmackowiak.nativeANE.dialogs.support.NativeTextField;
	import pl.mateuszmackowiak.nativeANE.dialogs.support.iNativeDialog;
	import pl.mateuszmackowiak.nativeANE.events.NativeDialogEvent;
	import pl.mateuszmackowiak.nativeANE.events.NativeDialogListEvent;
	import pl.mateuszmackowiak.nativeANE.notifications.Toast;
}
public class Scratch extends Sprite {
    // Version
    public static const versionString:String = 'v426';
    private static const REPORT_BUG_URL:String = 'https://github.com/scratchduino/forandroid/blob/master/README.md';
    private static const DONATE_URL:String = 'https://play.google.com/store/apps/details?id=air.ru.scratchduino.android.appdonate';
    public static var app:Scratch; // static reference to the app, used for debugging

    // Display modes
    public var editMode:Boolean; // true when project editor showing, false when only the player is showing
    public var isOffline:Boolean; // true when running as an offline (i.e. stand-alone) app
    public var isSmallPlayer:Boolean; // true when displaying as a scaled-down player (e.g. in search results)
    public var stageIsContracted:Boolean; // true when the stage is half size to give more space on small screens
    public var isIn3D:Boolean;
    public var render3D:IRenderIn3D;
    public var isArmCPU:Boolean;
    public var jsEnabled:Boolean = false; // true when the SWF can talk to the webpage

    // Runtime
    public var runtime:ScratchRuntime;
    public var interp:Interpreter;
    public var extensionManager:ExtensionManager;
    public var server:Server;
    public var gh:GestureHandler;
    public var projectID:String = '';
    public var projectOwner:String = '';
    public var projectIsPrivate:Boolean;
    public var oldWebsiteURL:String = '';
    public var loadInProgress:Boolean;
    public var debugOps:Boolean = false;
    public var debugOpCmd:String = '';

    public var connector:IConnector;
    public var robotCommunicator:IRobotCommunicator = null;

    protected var autostart:Boolean;
    private var viewedObject:ScratchObj;
    private var lastTab:String = 'scripts';
    protected var wasEdited:Boolean; // true if the project was edited and autosaved
    private var _usesUserNameBlock:Boolean = false;
    protected var languageChanged:Boolean; // set when language changed

    // UI Elements
    public var playerBG:Shape;
    public var palette:BlockPalette;
    public var scriptsPane:ScriptsPane;
    public var stagePane:ScratchStage;
    public var mediaLibrary:MediaLibrary;
    public var lp:LoadProgress;
    public var cameraDialog:CameraDialog;

    // UI Parts
    public var libraryPart:LibraryPart;
    protected var topBarPart:TopBarPart;
    protected var stagePart:StagePart;
    private var tabsPart:TabsPart;
    protected var scriptsPart:ScriptsPart;
    public var imagesPart:ImagesPart;
    public var soundsPart:SoundsPart;

    public var scratchBoardPart:ScratchBoardPart;
    public const tipsBarClosedWidth:int = 17;

    public static var isShowingTextInputDialog:Boolean;

    /* Default directory for projects */
    TARGET::android {
        private static const scratchProjectsDirectory:File = File.userDirectory.resolvePath("scratch-projects");
        private static var currentProjectsDirectory:File;
    }

    public function Scratch() {
        loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, uncaughtErrorHandler);
        app = this;

        // This one must finish before most other queries can start, so do it separately
        determineJSAccess();
    }

    protected function initialize():void {
        isOffline = loaderInfo.url.indexOf('http:') == -1;
        checkFlashVersion();
        initServer();

        isShowingTextInputDialog = false;

        stage.align = StageAlign.TOP_LEFT;
        stage.scaleMode = StageScaleMode.NO_SCALE;

        stage.frameRate = 30;

        Block.setFonts(10, 9, true, 0); // default font sizes
        Block.MenuHandlerFunction = BlockMenus.BlockMenuHandler;
        CursorTool.init(this);
        app = this;

        stagePane = new ScratchStage();
        gh = new GestureHandler(this, (loaderInfo.parameters['inIE'] == 'true'));
        initInterpreter();
        initRuntime();
        initExtensionManager();
        Translator.initializeLanguageList();

        playerBG = new Shape(); // create, but don't add
        addParts();

        stage.addEventListener(MouseEvent.MOUSE_DOWN, gh.mouseDown);
        stage.addEventListener(MouseEvent.MOUSE_MOVE, gh.mouseMove);
        stage.addEventListener(MouseEvent.MOUSE_UP, gh.mouseUp);
        stage.addEventListener(MouseEvent.MOUSE_WHEEL, gh.mouseWheel);
        stage.addEventListener('rightClick', gh.rightMouseClick);
        stage.addEventListener(KeyboardEvent.KEY_DOWN, runtime.keyDown);
        stage.addEventListener(KeyboardEvent.KEY_UP, runtime.keyUp);
        stage.addEventListener(KeyboardEvent.KEY_DOWN, keyDown); // to handle escape key
        stage.addEventListener(Event.ENTER_FRAME, step);
        stage.addEventListener(Event.RESIZE, onResize);
        TARGET::android {
            addEventListener(Event.DEACTIVATE, onPause);
            addEventListener(Event.ACTIVATE, onResume);
        }
        setEditMode(startInEditMode());

        // install project before calling fixLayout()
        if (editMode) runtime.installNewProject();
        else runtime.installEmptyProject();

        initCatSprite();
        fixLayout();
        TARGET::android {
            connector = new AndroidConnector();
        }

        TARGET::desktop {
            robotCommunicator = new DesktopRobotCommunicator(refreshAnalogs);
        }

        //Analyze.collectAssets(0, 119110);
        //Analyze.checkProjects(56086, 64220);
        //Analyze.countMissingAssets();

        // make stage small at startup
        toggleSmallStage();
    }


    function refreshAnalogs(data:Array):void {
        for (var i:int = 0; i < data.length; ++i) {
            runtime.analogs[i] = data[i];
            setAnalogText(i, data[i]);
        }
    }

    TARGET::android {
        private function onResume(event:Event):void {
            robotCommunicator.setActive(true);
        }

        private function onPause(event:Event):void {
            robotCommunicator.setActive(false);
            runtime.resetAnalogs();
            var projectFileName:String = projectName();
            if (projectFileName.length == 0 || projectFileName == ' ')
                return;
            saveCurrentProject();
        }
    }
	public function setAnalogText(index:int, text:String):void {
		scratchBoardPart.setAnalogText(index, text);
	}
	
	protected function initCatSprite():void {
		var initSprite:ScratchSprite = new ScratchSprite();
		initSprite.setInitialCostume(ScratchCostume.catBitmapCostume(Translator.map('costume1'), false));
		app.addNewSprite(initSprite, false);
	}
	
	protected function initTopBarPart():void {
		topBarPart = new TopBarPart(this);
	}

	protected function initInterpreter():void {
		interp = new Interpreter(this);
	}

	protected function initRuntime():void {
		runtime = new ScratchRuntime(this, interp);
	}

	protected function initExtensionManager():void {
		extensionManager = new ExtensionManager(this);
	}

	protected function initServer():void {
		server = new Server();
	}

	protected function setupExternalInterface(oldWebsitePlayer:Boolean):void {
		if (!jsEnabled) return;

		addExternalCallback('ASloadExtension', extensionManager.loadRawExtension);
		addExternalCallback('ASextensionCallDone', extensionManager.callCompleted);
		addExternalCallback('ASextensionReporterDone', extensionManager.reporterCompleted);
	}

	public function showTip(tipName:String):void {}
	public function closeTips():void {}
	public function reopenTips():void {}
	public function tipsWidth():int { return 0; }

	protected function startInEditMode():Boolean {
		return isOffline;
	}

	public function getMediaLibrary(type:String, whenDone:Function):MediaLibrary {
		return new MediaLibrary(this, type, whenDone);
	}

	public function getMediaPane(app:Scratch, type:String):MediaPane {
		return new MediaPane(app, type);
	}

	public function getScratchStage():ScratchStage {
		return new ScratchStage();
	}

	public function getPaletteBuilder():PaletteBuilder {
		return new PaletteBuilder(this);
	}

	private function uncaughtErrorHandler(event:UncaughtErrorEvent):void
	{
		if (event.error is Error)
		{
			var error:Error = event.error as Error;
			logException(error);
		}
		else if (event.error is ErrorEvent)
		{
			var errorEvent:ErrorEvent = event.error as ErrorEvent;
			logMessage(errorEvent.toString());
		}
	}

	public function log(s:String):void {
		trace(s);
	}

	public function logException(e:Error):void {}
	public function logMessage(msg:String, extra_data:Object=null):void {}
	public function loadProjectFailed():void {}

	protected function checkFlashVersion():void {
		{
			if (Capabilities.playerType != "Desktop" || Capabilities.version.indexOf('IOS') === 0) {
				var versionString:String = Capabilities.version.substr(Capabilities.version.indexOf(' ') + 1);
				var versionParts:Array = versionString.split(',');
				var majorVersion:int = parseInt(versionParts[0]);
				var minorVersion:int = parseInt(versionParts[1]);
				if ((majorVersion > 11 || (majorVersion == 11 && minorVersion >= 7)) && !isArmCPU && Capabilities.cpuArchitecture == 'x86') {
					render3D = (new DisplayObjectContainerIn3D() as IRenderIn3D);
					render3D.setStatusCallback(handleRenderCallback);
					return;
				}
			}
		}

		render3D = null;
	}

	protected function handleRenderCallback(enabled:Boolean):void {
		if(!enabled) {
			go2D();
			render3D = null;
		}
		else {
			for(var i:int=0; i<stagePane.numChildren; ++i) {
				var spr:ScratchSprite = (stagePane.getChildAt(i) as ScratchSprite);
				if(spr) {
					spr.clearCachedBitmap();
					spr.updateCostume();
					spr.applyFilters();
				}
			}
			stagePane.clearCachedBitmap();
			stagePane.updateCostume();
			stagePane.applyFilters();
		}
	}

	public function clearCachedBitmaps():void {
		for(var i:int=0; i<stagePane.numChildren; ++i) {
			var spr:ScratchSprite = (stagePane.getChildAt(i) as ScratchSprite);
			if(spr) spr.clearCachedBitmap();
		}
		stagePane.clearCachedBitmap();

		// unsupported technique that seems to force garbage collection
		try {
			new LocalConnection().connect('foo');
			new LocalConnection().connect('foo');
		} catch (e:Error) {}
	}

	public function go3D():void {
		if(!render3D || isIn3D) return;

		var i:int = stagePart.getChildIndex(stagePane);
		stagePart.removeChild(stagePane);
		render3D.setStage(stagePane, stagePane.penLayer);
		stagePart.addChildAt(stagePane, i);
		isIn3D = true;
	}

	public function go2D():void {
		if(!render3D || !isIn3D) return;

		var i:int = stagePart.getChildIndex(stagePane);
		stagePart.removeChild(stagePane);
		render3D.setStage(null, null);
		stagePart.addChildAt(stagePane, i);
		isIn3D = false;
		for(i=0; i<stagePane.numChildren; ++i) {
			var spr:ScratchSprite = (stagePane.getChildAt(i) as ScratchSprite);
			if(spr) {
				spr.clearCachedBitmap();
				spr.updateCostume();
				spr.applyFilters();
			}
		}
		stagePane.clearCachedBitmap();
		stagePane.updateCostume();
		stagePane.applyFilters();
	}

	protected function determineJSAccess():void {
		// After checking for JS access, call initialize().
		initialize();
	}

	private var debugRect:Shape;
	public function showDebugRect(r:Rectangle):void {
		// Used during debugging...
		var p:Point = stagePane.localToGlobal(new Point(0, 0));
		if (!debugRect) debugRect = new Shape();
		var g:Graphics = debugRect.graphics;
		g.clear();
		if (r) {
			g.lineStyle(2, 0xFFFF00);
			g.drawRect(p.x + r.x, p.y + r.y, r.width, r.height);
			addChild(debugRect);
		}
	}

	public function strings():Array {
		return [
			'a copy of the project file on your computer.',
			'Project not saved!', 'Save now', 'Not saved; project did not load.',
			'Save now', 'Saved',
			'Revert', 'Undo Revert', 'Reverting...',
			'Throw away all changes since opening this project?',
		];
	}

	public function viewedObj():ScratchObj { return viewedObject; }
	public function stageObj():ScratchStage { return stagePane; }
	public function projectName():String { return stagePart.projectName(); }
	public function highlightSprites(sprites:Array):void { libraryPart.highlight(sprites); }
	public function refreshImageTab(fromEditor:Boolean):void { imagesPart.refresh(fromEditor); }
	public function refreshSoundTab():void { soundsPart.refresh(); }
	public function selectCostume():void { imagesPart.selectCostume(); }
	public function selectSound(snd:ScratchSound):void { soundsPart.selectSound(snd); }
	public function clearTool():void { CursorTool.setTool(null); topBarPart.clearToolButtons(); }
	public function tabsRight():int { return tabsPart.x + tabsPart.w; }
	public function enableEditorTools(flag:Boolean):void { imagesPart.editor.enableTools(flag); }

	public function get usesUserNameBlock():Boolean {
		return _usesUserNameBlock;
	}

	public function set usesUserNameBlock(value:Boolean):void {
		_usesUserNameBlock = value;
		stagePart.refresh();
	}

	public function updatePalette(clearCaches:Boolean = true):void {
		// Note: updatePalette() is called after changing variable, list, or procedure
		// definitions, so this is a convenient place to clear the interpreter's caches.
		if (isShowing(scriptsPart)) scriptsPart.updatePalette();
		if (clearCaches) runtime.clearAllCaches();
	}

	public function setProjectName(s:String):void {
		if (s.slice(-3) == '.sb') s = s.slice(0, -3);
		if (s.slice(-4) == '.sb2') s = s.slice(0, -4);
		stagePart.setProjectName(s);
	}

	protected var wasEditing:Boolean;
	public function setPresentationMode(enterPresentation:Boolean):void {
		if (enterPresentation) {
			wasEditing = editMode;
			if (wasEditing) {
				setEditMode(false);
				if(jsEnabled) externalCall('tip_bar_api.hide');
			}
		} else {
			if (wasEditing) {
				setEditMode(true);
				if(jsEnabled) externalCall('tip_bar_api.show');
			}
		}
		if (isOffline) {
			stage.displayState = enterPresentation ? StageDisplayState.FULL_SCREEN_INTERACTIVE : StageDisplayState.NORMAL;
		}
		for each (var o:ScratchObj in stagePane.allObjects()) o.applyFilters();

		if (lp) fixLoadProgressLayout();
		stagePane.updateCostume();
		{ if(isIn3D) render3D.onStageResize(); }
	}

	private function keyDown(evt:KeyboardEvent):void {
		// Escape exists presentation mode.
		if ((evt.charCode == 27) && stagePart.isInPresentationMode()) {
			setPresentationMode(false);
			stagePart.exitPresentationMode();
		}
		// Handle enter key
//		else if(evt.keyCode == 13 && !stage.focus) {
//			stagePart.playButtonPressed(null);
//			evt.preventDefault();
//			evt.stopImmediatePropagation();
//		}
		// Handle ctrl-m and toggle 2d/3d mode
		else if(evt.ctrlKey && evt.charCode == 109) {
			{ isIn3D ? go2D() : go3D(); }
			evt.preventDefault();
			evt.stopImmediatePropagation();
		}
	}

	private function setSmallStageMode(flag:Boolean):void {
		stageIsContracted = flag;
		stagePart.refresh();
		fixLayout();
		libraryPart.refresh();
		tabsPart.refresh();
		stagePane.applyFilters();
		stagePane.updateCostume();
	}

	public function projectLoaded():void {
		removeLoadProgressBox();
		System.gc();
		if (autostart) runtime.startGreenFlags(true);
		saveNeeded = false;

		// translate the blocks of the newly loaded project
		for each (var o:ScratchObj in stagePane.allObjects()) {
			o.updateScriptsAfterTranslation();
		}
	}

	protected function step(e:Event):void {
		// Step the runtime system and all UI components.
		gh.step();
		runtime.stepRuntime();
		Transition.step(null);
		stagePart.step();
		libraryPart.step();
		scriptsPart.step();
		imagesPart.step();
	}

	public function updateSpriteLibrary(sortByIndex:Boolean = false):void { libraryPart.refresh() }
	public function threadStarted():void { stagePart.threadStarted() }

	public function selectSprite(obj:ScratchObj):void {
		if (isShowing(imagesPart)) imagesPart.editor.shutdown();
		if (isShowing(soundsPart)) soundsPart.editor.shutdown();
		viewedObject = obj;
		libraryPart.refresh();
		tabsPart.refresh();
		if (isShowing(imagesPart)) {
			imagesPart.refresh();
		}
		if (isShowing(soundsPart)) {
			soundsPart.currentIndex = 0;
			soundsPart.refresh();
		}
		if (isShowing(scriptsPart)) {
			scriptsPart.updatePalette();
			scriptsPane.viewScriptsFor(obj);
			scriptsPart.updateSpriteWatermark();
		}
	}

	public function setTab(tabName:String):void {
		if (isShowing(imagesPart)) imagesPart.editor.shutdown();
		if (isShowing(soundsPart)) soundsPart.editor.shutdown();
		hide(scriptsPart);
		hide(imagesPart);
		hide(soundsPart);
		if (!editMode) return;
		if (tabName == 'images') {
			show(imagesPart);
			imagesPart.refresh();
		} else if (tabName == 'sounds') {
			soundsPart.refresh();
			show(soundsPart);
		} else if (tabName && (tabName.length > 0)) {
			tabName = 'scripts';
			scriptsPart.updatePalette();
			scriptsPane.viewScriptsFor(viewedObject);
			scriptsPart.updateSpriteWatermark();
			show(scriptsPart);
		}
		show(tabsPart);
		show(stagePart); // put stage in front
		tabsPart.selectTab(tabName);
		lastTab = tabName;
		if (saveNeeded) setSaveNeeded(true); // save project when switching tabs, if needed (but NOT while loading!)
	}

	public function installStage(newStage:ScratchStage):void {
		var showGreenflagOverlay:Boolean = shouldShowGreenFlag();
		stagePart.installStage(newStage, showGreenflagOverlay);
		selectSprite(newStage);
		libraryPart.refresh();
		setTab('scripts');
		scriptsPart.resetCategory();
		wasEdited = false;
	}

	protected function shouldShowGreenFlag():Boolean {
		return !(autostart || editMode);
	}

	protected function addParts():void {
		initTopBarPart();
		stagePart = getStagePart();
		libraryPart = getLibraryPart();
		tabsPart = new TabsPart(this);
		scriptsPart = new ScriptsPart(this);
		imagesPart = new ImagesPart(this);
		soundsPart = new SoundsPart(this);
		scratchBoardPart = new ScratchBoardPart(this);
		addChild(topBarPart);
		addChild(scratchBoardPart);
		addChild(stagePart);
		addChild(libraryPart);
		addChild(tabsPart);
	}

	protected function getStagePart():StagePart {
		return new StagePart(this);
	}

	protected function getLibraryPart():LibraryPart {
		return new LibraryPart(this);
	}

	public function fixExtensionURL(javascriptURL:String):String {
		return javascriptURL;
	}

	// -----------------------------
	// UI Modes and Resizing
	//------------------------------

	public function setEditMode(newMode:Boolean):void {
		Menu.removeMenusFrom(stage);
		editMode = newMode;
		if (editMode) {
			interp.showAllRunFeedback();
			hide(playerBG);
			show(topBarPart);
			show(scratchBoardPart);
			show(libraryPart);
			show(tabsPart);
			setTab(lastTab);
			stagePart.hidePlayButton();
			runtime.edgeTriggersEnabled = true;
		} else {
			addChildAt(playerBG, 0); // behind everything
			playerBG.visible = false;
			hide(topBarPart);
			hide(libraryPart);
			hide(tabsPart);
			hide(scratchBoardPart);
			setTab(null); // hides scripts, images, and sounds
		}
		stagePane.updateListWatchers();
		show(stagePart); // put stage in front
		fixLayout();
		stagePart.refresh();
	}

	protected function hide(obj:DisplayObject):void { if (obj.parent) obj.parent.removeChild(obj) }
	protected function show(obj:DisplayObject):void { addChild(obj) }
	protected function isShowing(obj:DisplayObject):Boolean { return obj.parent != null }

	public function onResize(e:Event):void {
		fixLayout();
	}

	public function fixLayout():void {
		TARGET::desktop {
			var w:int = stage.stageWidth;
			var h:int = stage.stageHeight - 1; // fix to show bottom border...
			w = Math.ceil(w / scaleX);
			h = Math.ceil(h / scaleY);
		}
		TARGET::android {
			var w:int = 1280;
			var h:int = 680;
			if (stage.stageWidth < 1280) {
				w = 1024;
				h = 580;
				ScratchObj.STAGEH = 360 * 3 / 4;
			}
			scaleX = 1.0 * stage.stageWidth / w;
			scaleY = 1.0 * stage.stageHeight / h;
		}
		updateLayout(w, h);
	}

	protected function updateLayout(w:int, h:int):void {
		const SMALL_STAGE_W:int = ScratchObj.STAGEW / 2;
		const SMALL_STAGE_H:int = ScratchObj.STAGEH / 2;
		const BIG_STAGE_W:int = ScratchObj.STAGEW;
		const BIG_STAGE_H:int = ScratchObj.STAGEH;
		
		topBarPart.x = 0;
		topBarPart.y = 0;
		topBarPart.setWidthHeight(w, 28);
		
		var extraW:int = 2;
		var extraH:int = stagePart.computeTopBarHeight() + 1;
		if (editMode) {
			// adjust for global scale (from browser zoom)

			if (stageIsContracted) {
				stagePart.setWidthHeight(SMALL_STAGE_W + extraW, SMALL_STAGE_H /*nikita value 135*/ + extraH, 0.5);
			} else {
				stagePart.setWidthHeight(BIG_STAGE_W + extraW, BIG_STAGE_H/*nikita value 270*/ + extraH, 1);
			}
			stagePart.x = 5;
			stagePart.y = topBarPart.bottom() + 5;
			fixLoadProgressLayout();
		} else {
			drawBG();
			var pad:int = (w > 550) ? 16 : 0; // add padding for full-screen mode
			var scale:Number = Math.min((w - extraW - pad) / 480, (h - extraH - pad) / 360);
			scale = Math.max(0.01, scale);
			var scaledW:int = Math.floor((scale * 480) / 4) * 4; // round down to a multiple of 4
			scale = scaledW / 480;
			var playerW:Number = (scale * 480) + extraW;
			var playerH:Number = (scale * 360) + extraH;
			stagePart.setWidthHeight(playerW, playerH, scale);
			stagePart.x = int((w - playerW) / 2);
			stagePart.y = int((h - playerH) / 2);
			fixLoadProgressLayout();
			return;
		}
		
		var restHeight:Number = h - stagePart.bottom();
		var restWidth:Number = stagePart.w;
		var libraryPartHeight:Number = restHeight / 5 * 3 + 20 * (stageIsContracted ? 1 : 0);//remove add here
		var scratchBoardPartHeight:Number = restHeight / 5 * 2 - 20 * (stageIsContracted ? 1 : 0);//remove sub here
		TARGET::desktop {
			if (scratchBoardPartHeight < 125) {
				scratchBoardPartHeight = 125;
			}
		}
		
		scratchBoardPart.x = stagePart.x;
		scratchBoardPart.y = stagePart.bottom() + 18; // + 18
		scratchBoardPart.setWidthHeight(restWidth, scratchBoardPartHeight);
		
		libraryPart.x = scratchBoardPart.x;
		libraryPart.y = scratchBoardPart.bottom() + 5;
		libraryPart.setWidthHeight(restWidth, libraryPartHeight);
		
		tabsPart.x = stagePart.right() + 5;
		tabsPart.y = topBarPart.bottom() + 5;
		tabsPart.fixLayout();

		// the content area shows the part associated with the currently selected tab:
		var contentY:int = tabsPart.y + 27;
		w -= tipsWidth();
		updateContentArea(tabsPart.x, contentY, w - tabsPart.x - 6, h - contentY - 5, h);
	}

	protected function updateContentArea(contentX:int, contentY:int, contentW:int, contentH:int, fullH:int):void {
		imagesPart.x = soundsPart.x = scriptsPart.x = contentX;
		imagesPart.y = soundsPart.y = scriptsPart.y = contentY;
		imagesPart.setWidthHeight(contentW, contentH);
		soundsPart.setWidthHeight(contentW, contentH);
		scriptsPart.setWidthHeight(contentW, contentH);

		if (mediaLibrary) mediaLibrary.setWidthHeight(topBarPart.w, fullH);
		if (frameRateGraph) {
			frameRateGraph.y = stage.stageHeight - frameRateGraphH;
			addChild(frameRateGraph); // put in front
		}
		 { if (isIn3D) render3D.onStageResize(); }
	}

	private function drawBG():void {
		var g:Graphics = playerBG.graphics;
		g.clear();
		g.beginFill(0);
		g.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
	}

	// -----------------------------
	// Translations utilities
	//------------------------------

	public function translationChanged():void {
		// The translation has changed. Fix scripts and update the UI.
		// directionChanged is true if the writing direction (e.g. left-to-right) has changed.
		for each (var o:ScratchObj in stagePane.allObjects()) {
			o.updateScriptsAfterTranslation();
		}
		var uiLayer:Sprite = app.stagePane.getUILayer();
		for (var i:int = 0; i < uiLayer.numChildren; ++i) {
			var lw:ListWatcher = uiLayer.getChildAt(i) as ListWatcher;
			if (lw) lw.updateTranslation();
		}
		topBarPart.updateTranslation();
		stagePart.updateTranslation();
		libraryPart.updateTranslation();
		tabsPart.updateTranslation();
		updatePalette(false);
		imagesPart.updateTranslation();
		soundsPart.updateTranslation();
		scratchBoardPart.updateTranslation();
	}

	// -----------------------------
	// Menus
	//------------------------------
	public function showFileMenu(b:*):void {
		var m:Menu = new Menu(null, 'File', CSS.topBarColor, 28);
		m.addItem('New', createNewProject);
		m.addLine();

		// Derived class will handle this
		addFileMenuItems(b, m);

		m.showOnStage(stage, b.x, topBarPart.bottom() - 1);
	}

	protected function addFileMenuItems(b:*, m:Menu):void {
		m.addItem('Open', runtime.selectProjectFile);
        TARGET::android {
            m.addItem('Save', saveCurrentProject);
        }
        TARGET::desktop {
            m.addItem('Save', exportProjectToFile);
        }
		m.addItem('Save as', exportProjectToFile);
		if (canUndoRevert()) {
			m.addLine();
			m.addItem('Undo Revert', undoRevert);
		} else if (canRevert()) {
			m.addLine();
			m.addItem('Revert', revertToOriginalProject);
		}

		if (b.lastEvent.shiftKey) {
			m.addLine();
			m.addItem('Save Project Summary', saveSummary);
		}
		if (b.lastEvent.shiftKey && jsEnabled) {
			m.addLine();
			m.addItem('Import experimental extension', function():void {
				function loadJSExtension(dialog:DialogBox):void {
					var url:String = dialog.getField('URL').replace(/^\s+|\s+$/g, '');
					if (url.length == 0) return;
					externalCall('ScratchExtensions.loadExternalJS', null, url);
				}
				var d:DialogBox = new DialogBox(loadJSExtension);
				d.addTitle('Load Javascript Scratch Extension');
				d.addField('URL', 120);
				d.addAcceptCancelButtons('Load');
				d.showOnStage(app.stage);
			});
		}
	}

	public function showEditMenu(b:*):void {
		var m:Menu = new Menu(null, 'More', CSS.topBarColor, 28);
		m.addItem('Undelete', runtime.undelete, runtime.canUndelete());
		m.addLine();
		m.addItem('Small stage layout', toggleSmallStage, true, stageIsContracted);
		m.addItem('Turbo mode', toggleTurboMode, true, interp.turboMode);
		addEditMenuItems(b, m);
		var p:Point = b.localToGlobal(new Point(0, 0));
		m.showOnStage(stage, b.x, topBarPart.bottom() - 1);
	}

	protected function addEditMenuItems(b:*, m:Menu):void {
		m.addLine();
		m.addItem('Edit block colors', editBlockColors);
	}
	
	//Devices menu
	
	public function showHelpMenu(b:*):void {
		var m:Menu = new Menu(null, 'Help', CSS.topBarColor, 28);
		m.addItem('Report bug', reportBug);
		m.showOnStage(stage, b.x, topBarPart.bottom() - 1);
	}

    public function donate(b:*):void {//TODO write
        var urlReq:URLRequest = new URLRequest(DONATE_URL);
        navigateToURL(urlReq);
    }
	
	protected function reportBug():void { 
		var urlReq:URLRequest = new URLRequest(REPORT_BUG_URL); 
		navigateToURL(urlReq);
	}

    TARGET::android {
        public function showDevicesMenu(b:*):void {//for Android only
            var m:Menu = new Menu(null, 'Devices', CSS.topBarColor, 28);
            if (robotCommunicator != null)
                m.addItem('Disconnect', disconnectFromDevice);
            else
                m.addItem('Search devices', searchDevices);
            m.showOnStage(stage, b.x, topBarPart.bottom() - 1);
        }

        protected function searchDevices():void {//for Android only
            function showProgressDialog():void {
                var p:NativeProgressDialog = new NativeProgressDialog();
                p.addEventListener(NativeDialogEvent.CLOSED, onCloseDialog);
                p.setIndeterminate(true);
                p.title = Translator.map("Searching for devices");//TRANSLATE
                p.message = Translator.map("Please wait");//TRANSLATE
                p.showSpinner();
                progressPopup = p;
            }

            function onCloseDialog(event:NativeDialogEvent):void {
                var m:iNativeDialog = iNativeDialog(event.target);
                m.removeEventListener(NativeDialogEvent.CLOSED, onCloseDialog);
                m.dispose();
            }

            var progressPopup:NativeProgressDialog;

            var alreadyShown:Boolean = false;

            var error:int = connector.scanForVisibleDevices(
                    function ():void {
                        showProgressDialog();
                    },

                    function (devices:Vector.<IDevice>):void {
                        //trace("devices = " + devices);
                        var scratchNames:Vector.<Object> = new Vector.<Object>();
                        var scratchDevices:Vector.<IDevice> = new Vector.<IDevice>();
                        for each (var t:IDevice in devices) {
                            if (t.getName().substr(0, "Scratchduino".length) == "Scratchduino") {
                                scratchDevices.push(t);
                                scratchNames.push(t.getName());
                            }
                        }
                        if (scratchDevices.length != 0) {
                            var bluetoothDialog:NativeListDialog = new NativeListDialog();
                            bluetoothDialog.setTitle(Translator.map("Scratchduino devices"));
                            bluetoothDialog.dataProvider = scratchNames;
                            bluetoothDialog.buttons = Vector.<String>([Translator.map("OK"), Translator.map("Cancel")]);
                            bluetoothDialog.selectedIndex = 0;

                            bluetoothDialog.addEventListener(NativeDialogEvent.CLOSED, function (ev:Event):void {
                                var n:NativeListDialog = NativeListDialog(ev.target);
                                n.dispose();
                                var device:IDevice = scratchDevices[bluetoothDialog.selectedIndex];
                                device.addDeviceConnectedListener(function (bev:BluetoothDeviceEvent):void {
                                    trace("connected to ", device.getName());
                                    robotCommunicator = new AndroidRobotCommunicator(device, refreshAnalogs);
                                    Toast.show(Translator.map("Connected to ") + device.getName(), Toast.LENGTH_SHORT);
                                    tabsPart.refresh();
                                });

                                device.addDeviceConnectErrorListener(function (bev:BluetoothDeviceEvent):void {
                                    disconnect();
                                });

                                device.addDeviceDisconnectedListener(function (bev:BluetoothDeviceEvent):void {
                                    if (device == null)
                                        return;
                                    var name:String = device.getName();
                                    disconnect();
                                    if (alreadyShown)
                                        return;
                                    alreadyShown = true;
                                    NativeAlertDialog.showAlert(Translator.map("Lost connection to ") + name + ". " +
                                            Translator.map("Make sure that Bluetooth is enabled on robot and search for devices again"),
                                            Translator.map("Connection lost")).
                                            addEventListener(NativeDialogEvent.CLOSED, function ():void {
                                                alreadyShown = false;
                                            });
                                });

                                if (!device.isConnected())
                                    device.connect();

                            });

                            progressPopup.dispose();

                            bluetoothDialog.setCancelable(true);
                            bluetoothDialog.show();
                        } else {
                            progressPopup.dispose();
                            NativeAlertDialog.showAlert(Translator.map("There are no devices found. Make sure that Bluetooth is enabled on robot"), Translator.map("No devices found"));
                        }
                    }
            );
        }

        public function disconnect():void {
            runtime.resetAnalogs();
            tabsPart.refresh();
            if (robotCommunicator != null) {
                robotCommunicator.finishSession();
                robotCommunicator = null;
            }
        }

        protected function disconnectFromDevice():void {
            disconnect();
        }
    }
	
	protected function editBlockColors():void {
		var d:DialogBox = new DialogBox();
		d.addTitle('Edit Block Colors');
		d.addWidget(new BlockColorEditor());
		d.addButton('Close', d.cancel);
		d.showOnStage(stage, true);
	}

	protected function canExportInternals():Boolean {
		return false;
	}

	private function showAboutDialog():void {
		DialogBox.notify(
			'Scratch 2.0 ' + versionString,
			'\n\nCopyright © 2012 MIT Media Laboratory' +
			'\nAll rights reserved.' +
			'\n\nPlease do not distribute!', stage);
	}

	protected function createNewProject(ignore:* = null):void {
		function clearProject():void {
			startNewProject('', '');
			/*  Empty project has empty string name ("").
			 *  Used to determine whether to show project name picker dialog 
			 *  or not.
			 */
			setProjectName('');
			topBarPart.refresh();
			stagePart.refresh();
		}
		saveProjectAndThen(clearProject);
	}

	protected function saveProjectAndThen(postSaveAction:Function = null):void {
		// Give the user a chance to save their project, if needed, then call postSaveAction.
		function doNothing():void {}
		function cancel():void { d.cancel(); }
		function proceedWithoutSaving():void { d.cancel(); postSaveAction() }
		function save():void {
			d.cancel();
            TARGET::android {
                saveCurrentProject(); // if this succeeds, saveNeeded will become false
            }
            TARGET::desktop {
                exportProjectToFile();
            }
			saveNeeded = false;
			if (!saveNeeded) {
				postSaveAction();
			}
		}
		if (postSaveAction == null) {
			postSaveAction = doNothing;
		}
		if (!saveNeeded) {
			postSaveAction();
			return;
		}
		var d:DialogBox = new DialogBox();
		d.addTitle('Save project?');
		d.addButton('Save', save);
		d.addButton('Don\'t save', proceedWithoutSaving);
		d.addButton('Cancel', cancel);
		d.showOnStage(stage);
	}
	
	/*  This method attempts to save project. If project has some
	*   name alredy ( projectName().length > 0 actually ), it just saves current
	*   project to 'projectName()' + '.sb2' file. Otherwise,
	*   @exportProjectToFile() is called and user will be forced to
	*   pick a name for project.
	*/
    TARGET::android {
        protected function saveCurrentProject():void {
            function squeakSoundsConverted():void {
                scriptsPane.saveScripts(false);
                var zipData:ByteArray = projIO.encodeProjectAsZipFile(stagePane);
                var projectFileName:String = projectName();
                /*  Somewhere it is set to be one space, but we need an empty string
                 *  name for empty project to determine whether we should
                 *  save current project with an exiting name or pick a new one.
                 */
                if (projectFileName.length == 0 || projectFileName == ' ') {
                    exportProjectToFile();
                    return;
                }
                projectFileName = projectFileName + '.sb2';
                writeBytesToFile(projectFileName, zipData);
                setProjectName(projectFileName);
            }

            if (loadInProgress) {
                return;
            }
            var projIO:ProjectIO = new ProjectIO(this);
            projIO.convertSqueakSounds(stagePane, squeakSoundsConverted);
        }
    }

	/*  This method shows picker dialog, where user enters project name.
	 *  
	 */
	
	protected function exportProjectToFile(fromJS:Boolean = false):void {
		TARGET::android {
			var projectFileName:String;
			var zipData:ByteArray;

			function squeakSoundsConverted():void {
				scriptsPane.saveScripts(false);
				zipData = projIO.encodeProjectAsZipFile(stagePane);

				/*  Create Text input dialog, where user inputs name for project.
				 */

				var t:NativeTextInputDialog = new NativeTextInputDialog();
				t.setTitle(Translator.map("Choose project name"));
				t.setCancelable(true);
				/*  Any button will trigger CLOSED event, so we need only OK button.
				 *  Dialog can be canceled with Android back button or tapping anywhere
				 *  outide the dialog.
				 */
				t.buttons = Vector.<String>(["OK"/*, "Cancel"*/]);

				t.addEventListener(NativeDialogEvent.CANCELED, onCancelDialog);
				t.addEventListener(NativeDialogEvent.CLOSED, onCloseOKDialog);

				var v:Vector.<NativeTextField> = new Vector.<NativeTextField>();


				//creates a message text-field
				var message:NativeTextField = new NativeTextField(null);
				/*  Two extra spaces in the beginning and end to add some padding to message
				 */
				message.text = Translator.map("  To cancel, tap outside the dialog or press back button  ");
				message.editable = false;
				v.push(message);


				// create text-input
				var projectNameTextInput:NativeTextField = new NativeTextField("Project name");
				projectNameTextInput.displayAsPassword = false;
				projectNameTextInput.prompText = Translator.map("Project name");
				projectNameTextInput.softKeyboardType = SoftKeyboardType.DEFAULT;
				projectNameTextInput.addEventListener(Event.CHANGE, function (event:Event):void {
					var tf:NativeTextField = NativeTextField(event.target);
					projectFileName = tf.text;
				});
				// on return click
				projectNameTextInput.addEventListener(TextEvent.TEXT_INPUT, function (event:Event):void {
					var tf:NativeTextField = NativeTextField(event.target);
					tf.nativeTextInputDialog.hide(0);
					trace(projectFileName);
				});

				v.push(projectNameTextInput);

				t.textInputs = v;
				t.show(true);

			}

			/*function fileSaved(e:Event):void {
			 if (!fromJS) {
			 setProjectName(e.target.name);
			 }
			 }*/

			/* Handler for dialog's close event. Dialog is used for picking
			 *  filename for project. Text is saved in onChange event, this is
			 *  used only to remove handler and show dialog once again if
			 *  user entered empty string for project name.
			 */
			function onCloseOKDialog(event:NativeDialogEvent):void {
				var m:iNativeDialog = iNativeDialog(event.target);
				trace(event.target);
				m.removeEventListener(NativeDialogEvent.CLOSED, onCloseOKDialog);
				trace(event);
				m.dispose();

				projectFileName = fixFileName(projectFileName);
				if (projectFileName.length == 0 || projectFileName == ' ') {
					Toast.show("Project name must contain at least one symbol", Toast.LENGTH_SHORT);
					// create and show dialog again
					squeakSoundsConverted();
					return;
				}
				if (!StringUtils.endsWith(projectFileName, ".sb2")) {
					projectFileName = projectFileName + ".sb2";
				}
				setProjectName(projectFileName);
				writeBytesToFile(projectFileName, zipData);
			}

			function onCancelDialog(event:NativeDialogEvent):void {
				var m:iNativeDialog = iNativeDialog(event.target);
				trace(event.target);
				m.removeEventListener(NativeDialogEvent.CANCELED, onCloseOKDialog);
				trace(event);
				m.dispose();
			}

			if (loadInProgress) {
				return;
			}
			var projIO:ProjectIO = new ProjectIO(this);
			projIO.convertSqueakSounds(stagePane, squeakSoundsConverted);
		}
		TARGET::desktop {
			function squeakSoundsConvertedDesktop():void {
				scriptsPane.saveScripts(false);
				var defaultName:String = (projectName().length > 0) ? projectName() + '.sb2' : 'project.sb2';
				var zipData:ByteArray = projIO.encodeProjectAsZipFile(stagePane);
				var file:FileReference = new FileReference();
				file.addEventListener(Event.COMPLETE, fileSaved);
				file.save(zipData, fixFileName(defaultName));
			}
			function fileSaved(e:Event):void {
				if (!fromJS) setProjectName(e.target.name);
			}
			if (loadInProgress) return;
			var projIO:ProjectIO = new ProjectIO(this);
			projIO.convertSqueakSounds(stagePane, squeakSoundsConvertedDesktop);
		}
	}

	TARGET::android {
		private static function writeBytesToFile(fileName:String, data:ByteArray):void {
			var outFile:File = File.userDirectory.resolvePath("scratch-projects");
			outFile = outFile.resolvePath(fileName);
			var outStream:FileStream = new FileStream();
			outStream.open(outFile, FileMode.WRITE);
			outStream.writeBytes(data, 0, data.length);
			outStream.close();
		}
	}
	
	public static function fixFileName(s:String):String {
		/*  @param s can be null, because empty string from NativeTextDialog
		 *  is returned as null, but not as empty string. So fix
		 *  it to make further code work properly.
		 */
		if (s == null) {
			s = '';
		}
		// Replace illegal characters in the given string with dashes.
		const illegal:String = '\\/:*?"<>|%';
		var result:String = '';
		for (var i:int = 0; i < s.length; i++) {
			var ch:String = s.charAt(i);
			if ((i == 0) && ('.' == ch)) ch = '-'; // don't allow leading period
			result += (illegal.indexOf(ch) > -1) ? '-' : ch;
		}
		return result;
	}

	public function saveSummary():void {
		var name:String = (projectName() || "project") + ".txt";
		var file:FileReference = new FileReference();
		file.save(stagePane.getSummary(), fixFileName(name));
	}

	public function toggleSmallStage():void {
		setSmallStageMode(!stageIsContracted);
	}

	public function toggleTurboMode():void {
		interp.turboMode = !interp.turboMode;
		stagePart.refresh();
	}

	public function handleTool(tool:String, evt:MouseEvent):void { }

	public function showBubble(text:String, x:* = null, y:* = null, width:Number = 0):void {
		if (x == null) x = stage.mouseX;
		if (y == null) y = stage.mouseY;
		gh.showBubble(text, Number(x), Number(y), width);
	}

	// -----------------------------
	// Project Management and Sign in
	//------------------------------

	public function setLanguagePressed(b:IconButton):void {
		function setLanguage(lang:String):void {
			Translator.setLanguage(lang);
			languageChanged = true;
		}
		if (Translator.languages.length == 0) return; // empty language list
		var m:Menu = new Menu(setLanguage, 'Language', CSS.topBarColor, 28);
		if (b.lastEvent.shiftKey) {
			m.addItem('import translation file');
			m.addItem('set font size');
			m.addLine();
		}
		for each (var entry:Array in Translator.languages) {
			m.addItem(entry[1], entry[0], true, Translator.currentLang == entry[0]);
		}
		var p:Point = b.localToGlobal(new Point(0, 0));
		m.showOnStage(stage, b.x, topBarPart.bottom() - 1);
	}

	public function startNewProject(newOwner:String, newID:String):void {
		runtime.installNewProject();
		projectOwner = newOwner;
		projectID = newID;
		projectIsPrivate = true;
		loadInProgress = false;
		initCatSprite();
	}

	// -----------------------------
	// Save status
	//------------------------------

	public var saveNeeded:Boolean;

	public function setSaveNeeded(saveNow:Boolean = false):void {
		saveNow = false;
		// Set saveNeeded flag and update the status string.
		saveNeeded = true;
		if (!wasEdited) saveNow = true; // force a save on first change
		clearRevertUndo();
	}

	protected function clearSaveNeeded():void {
		// Clear saveNeeded flag and update the status string.
		function twoDigits(n:int):String { return ((n < 10) ? '0' : '') + n }
		saveNeeded = false;
		wasEdited = true;
	}

	// -----------------------------
	// Project Reverting
	//------------------------------

	protected var originalProj:ByteArray;
	private var revertUndo:ByteArray;

	public function saveForRevert(projData:ByteArray, isNew:Boolean, onServer:Boolean = false):void {
		originalProj = projData;
		revertUndo = null;
	}

	protected function doRevert():void {
		runtime.installProjectFromData(originalProj, false);
	}

	protected function revertToOriginalProject():void {
		function preDoRevert():void {
			revertUndo = new ProjectIO(Scratch.app).encodeProjectAsZipFile(stagePane);
			doRevert();
		}
		if (!originalProj) return;
		DialogBox.confirm('Throw away all changes since opening this project?', stage, preDoRevert);
	}

	protected function undoRevert():void {
		if (!revertUndo) return;
		runtime.installProjectFromData(revertUndo, false);
		revertUndo = null;
	}

	protected function canRevert():Boolean { return originalProj != null }
	protected function canUndoRevert():Boolean { return revertUndo != null }
	private function clearRevertUndo():void { revertUndo = null }

	public function addNewSprite(spr:ScratchSprite, showImages:Boolean = false, atMouse:Boolean = false):void {
		var c:ScratchCostume, byteCount:int;
		for each (c in spr.costumes) {
			if (!c.baseLayerData) c.prepareToSave()
			byteCount += c.baseLayerData.length;
		}
		if (!okayToAdd(byteCount)) return; // not enough room
		spr.objName = stagePane.unusedSpriteName(spr.objName);
		spr.indexInLibrary = 1000000; // add at end of library
		spr.setScratchXY(int(200 * Math.random() - 100), int(100 * Math.random() - 50));
		if (atMouse) spr.setScratchXY(stagePane.scratchMouseX(), stagePane.scratchMouseY());
		stagePane.addChild(spr);
		selectSprite(spr);
		setTab(showImages ? 'images' : 'scripts');
		setSaveNeeded(true);
		libraryPart.refresh();
		for each (c in spr.costumes) {
			if (ScratchCostume.isSVGData(c.baseLayerData)) c.setSVGData(c.baseLayerData, false);
		}
	}

	public function addSound(snd:ScratchSound, targetObj:ScratchObj = null):void {
		if (snd.soundData && !okayToAdd(snd.soundData.length)) return; // not enough room
		if (!targetObj) targetObj = viewedObj();
		snd.soundName = targetObj.unusedSoundName(snd.soundName);
		targetObj.sounds.push(snd);
		setSaveNeeded(true);
		if (targetObj == viewedObj()) {
			soundsPart.selectSound(snd);
			setTab('sounds');
		}
	}

	public function addCostume(c:ScratchCostume, targetObj:ScratchObj = null):void {
		if (!c.baseLayerData) c.prepareToSave();
		if (!okayToAdd(c.baseLayerData.length)) return; // not enough room
		if (!targetObj) targetObj = viewedObj();
		c.costumeName = targetObj.unusedCostumeName(c.costumeName);
		targetObj.costumes.push(c);
		targetObj.showCostumeNamed(c.costumeName);
		setSaveNeeded(true);
		if (targetObj == viewedObj()) setTab('images');
	}

	public function okayToAdd(newAssetBytes:int):Boolean {
		// Return true if there is room to add an asset of the given size.
		// Otherwise, return false and display a warning dialog.
		const assetByteLimit:int = 50 * 1024 * 1024; // 50 megabytes
		var assetByteCount:int = newAssetBytes;
		for each (var obj:ScratchObj in stagePane.allObjects()) {
			for each (var c:ScratchCostume in obj.costumes) {
				if (!c.baseLayerData) c.prepareToSave();
				assetByteCount += c.baseLayerData.length;
			}
			for each (var snd:ScratchSound in obj.sounds) assetByteCount += snd.soundData.length;
		}
		if (assetByteCount > assetByteLimit) {
			var overBy:int = Math.max(1, (assetByteCount - assetByteLimit) / 1024);
			DialogBox.notify(
				'Sorry!',
				'Adding that media asset would put this project over the size limit by ' + overBy + ' KB\n' +
				'Please remove some costumes, backdrops, or sounds before adding additional media.',
				stage);
			return false;
		}
		return true;
	}
	// -----------------------------
	// Flash sprite (helps connect a sprite on the stage with a sprite library entry)
	//------------------------------

	public function flashSprite(spr:ScratchSprite):void {
		function doFade(alpha:Number):void { box.alpha = alpha }
		function deleteBox():void { if (box.parent) { box.parent.removeChild(box) }}
		var r:Rectangle = spr.getVisibleBounds(this);
		var box:Shape = new Shape();
		box.graphics.lineStyle(3, CSS.overColor, 1, true);
		box.graphics.beginFill(0x808080);
		box.graphics.drawRoundRect(0, 0, r.width, r.height, 12, 12);
		box.x = r.x;
		box.y = r.y;
		addChild(box);
		Transition.cubic(doFade, 1, 0, 0.5, deleteBox);
	}

	// -----------------------------
	// Download Progress
	//------------------------------

	public function addLoadProgressBox(title:String):void {
		removeLoadProgressBox();
		lp = new LoadProgress();
		lp.setTitle(title);
		stage.addChild(lp);
		fixLoadProgressLayout();
	}

	public function removeLoadProgressBox():void {
		if (lp && lp.parent) lp.parent.removeChild(lp);
		lp = null;
	}

	private function fixLoadProgressLayout():void {
		if (!lp) return;
		var p:Point = stagePane.localToGlobal(new Point(0, 0));
		lp.scaleX = stagePane.scaleX;
		lp.scaleY = stagePane.scaleY;
		lp.x = int(p.x + ((stagePane.width - lp.width) / 2));
		lp.y = int(p.y + ((stagePane.height - lp.height) / 2));
	}

	// -----------------------------
	// Frame rate readout (for use during development)
	//------------------------------

	private var frameRateReadout:TextField;
	private var firstFrameTime:int;
	private var frameCount:int;

	protected function addFrameRateReadout(x:int, y:int, color:uint = 0):void {
		frameRateReadout = new TextField();
		frameRateReadout.autoSize = TextFieldAutoSize.LEFT;
		frameRateReadout.selectable = false;
		frameRateReadout.background = false;
		frameRateReadout.defaultTextFormat = new TextFormat(CSS.font, 12, color);
		frameRateReadout.x = x;
		frameRateReadout.y = y;
		addChild(frameRateReadout);
		frameRateReadout.addEventListener(Event.ENTER_FRAME, updateFrameRate);
	}

	private function updateFrameRate(e:Event):void {
		frameCount++;
		if (!frameRateReadout) return;
		var now:int = getTimer();
		var msecs:int = now - firstFrameTime;
		if (msecs > 500) {
			var fps:Number = Math.round((1000 * frameCount) / msecs);
			frameRateReadout.text = fps + ' fps (' + Math.round(msecs / frameCount) + ' msecs)';
			firstFrameTime = now;
			frameCount = 0;
		}
	}

	// TODO: Remove / no longer used
	private const frameRateGraphH:int = 150;
	private var frameRateGraph:Shape;
	private var nextFrameRateX:int;
	private var lastFrameTime:int;

	private function addFrameRateGraph():void {
		addChild(frameRateGraph = new Shape());
		frameRateGraph.y = stage.stageHeight - frameRateGraphH;
		clearFrameRateGraph();
		stage.addEventListener(Event.ENTER_FRAME, updateFrameRateGraph);
	}

	public function clearFrameRateGraph():void {
		var g:Graphics = frameRateGraph.graphics;
		g.clear();
		g.beginFill(0xFFFFFF);
		g.drawRect(0, 0, stage.stageWidth, frameRateGraphH);
		nextFrameRateX = 0;
	}

	private function updateFrameRateGraph(evt:*):void {
		var now:int = getTimer();
		var msecs:int = now - lastFrameTime;
		lastFrameTime = now;
		var c:int = 0x505050;
		if (msecs > 40) c = 0xE0E020;
		if (msecs > 50) c = 0xA02020;

		if (nextFrameRateX > stage.stageWidth) clearFrameRateGraph();
		var g:Graphics = frameRateGraph.graphics;
		g.beginFill(c);
		var barH:int = Math.min(frameRateGraphH, msecs / 2);
		g.drawRect(nextFrameRateX, frameRateGraphH - barH, 1, barH);
		nextFrameRateX++;
	}

	// -----------------------------
	// Camera Dialog
	//------------------------------

	public function openCameraDialog(savePhoto:Function):void {
		closeCameraDialog();
		cameraDialog = new CameraDialog(savePhoto);
		cameraDialog.fixLayout();
		cameraDialog.x = (stage.stageWidth - cameraDialog.width) / 2;
		cameraDialog.y = (stage.stageHeight - cameraDialog.height) / 2;
		addChild(cameraDialog);
	}

	public function closeCameraDialog():void {
		if (cameraDialog) {
			cameraDialog.closeDialog();
			cameraDialog = null;
		}
	}

	// Misc.
	public function createMediaInfo(obj:*, owningObj:ScratchObj = null):MediaInfo {
		return new MediaInfo(obj, owningObj);
	}

	static public function loadSingleFile(fileLoaded:Function, filters:Array = null):void {
		TARGET::android {
			var selectedIndex:int;

			/* Create directory if it doesn't exist (does nothing if already exist) */
			scratchProjectsDirectory.createDirectory();

			/* Create dialog, where user can select project file to load. */
			var m:NativeListDialog = new NativeListDialog();
			m.setCancelable(true);
			m.addEventListener(NativeDialogEvent.CANCELED, dialogCanceled);
			m.addEventListener(NativeDialogEvent.OPENED, trace);
			m.addEventListener(NativeDialogEvent.CLOSED, readSelected);
			m.addEventListener(NativeDialogListEvent.LIST_CHANGE, fileSelected);

			m.buttons = Vector.<String>([Translator.map("OK"), Translator.map("Cancel")]);
			m.title = Translator.map("Select project");
			m.message = "Message";

			if (currentProjectsDirectory == null) {
				currentProjectsDirectory = scratchProjectsDirectory;
			}
			var curDirFiles:Array = currentProjectsDirectory.getDirectoryListing();
			curDirFiles.sort(function (x:File, y:File):int {

				function cmp(f:File):int {
					return f.isDirectory ? 0 : 1;
				}

				var a:int = cmp(x);
				var b:int = cmp(y);
				if (a != b) {
					return a - b;
				} else {
					if (x.name < y.name) return -1;
					else if (x.name == y.name) return 0;
					else return 1;
				}

			});
			var files:Vector.<File> = new Vector.<File>();
			var names:Array = new Array();
			if (currentProjectsDirectory.parent != null) {
				names.push("..");
				files.push(currentProjectsDirectory.parent);
			}
			for (var i:uint = 0; i < curDirFiles.length; i++) {
				var name:String = curDirFiles[i].name;
				if (curDirFiles[i].isDirectory) {
					files.push(curDirFiles[i]);
					names.push("[" + name + "]");
				} else if (StringUtils.endsWith(name, ".sb2")) {
					files.push(curDirFiles[i]);
					names.push(name.substring(0, name.length - ".sb2".length));
				} else if (StringUtils.endsWith(name, ".sb")) {
					files.push(curDirFiles[i]);
					names.push(name.substring(0, name.length - ".sb".length));
				}
			}

			m.dataProvider = Vector.<Object>(names);
			m.displayMode = NativeListDialog.DISPLAY_MODE_SINGLE;
			m.selectedIndex = -1;
			m.show();

			/* Seems to be easily replaced by @trace function.
			 * Disposing is redundant because this event is always dispatched after CLOSED
			 */
			function dialogCanceled(event:NativeDialogEvent):void {
				var d:NativeListDialog = NativeListDialog(event.target);

				trace("Dialog canceled");

				d.dispose();
			}

			function fileSelected(event:NativeDialogListEvent):void {
				var d:NativeListDialog = NativeListDialog(event.target);

				selectedIndex = d.selectedIndex;
				trace("Selected index:", selectedIndex);

				d.dispose();
				if (selectedIndex == -1) {
					return;
				}

				if (files[selectedIndex].isDirectory) {
					currentProjectsDirectory = files[selectedIndex];
					loadSingleFile(fileLoaded, filters);
				} else {
					var projectFile:FileReference = FileReference(files[selectedIndex]);
					projectFile.addEventListener(Event.COMPLETE, fileLoaded);
					projectFile.load();
				}
			}

			function readSelected(event:NativeDialogEvent):void {
				var m:NativeListDialog = NativeListDialog(event.target);

				trace(event);

				var projectFile:FileReference = FileReference(files[selectedIndex]);
				projectFile.addEventListener(Event.COMPLETE, fileLoaded);
				projectFile.load();

				m.dispose();
			}
		}
		TARGET::desktop {
			function fileSelected1(event:Event):void {
				if (fileList.fileList.length > 0) {
					var file:FileReference = FileReference(fileList.fileList[0]);
					file.addEventListener(Event.COMPLETE, fileLoaded);
					file.load();
				}
			}

			var fileList:FileReferenceList = new FileReferenceList();
			fileList.addEventListener(Event.SELECT, fileSelected1);
			try {
				// Ignore the exception that happens when you call browse() with the file browser open
				fileList.browse(filters);
			} catch(e:*) {}
		}
	}

	// -----------------------------
	// External Interface abstraction
	//------------------------------

	public function externalInterfaceAvailable():Boolean {
		return false;
	}

	public function externalCall(functionName:String, returnValueCallback:Function = null, ...args):void {
		throw new IllegalOperationError('Must override this function.');
	}

	public function addExternalCallback(functionName:String, closure:Function):void {
		throw new IllegalOperationError('Must override this function.');
	}
}}
