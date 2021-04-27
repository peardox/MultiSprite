unit MainGameUnit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, CastleUIState,
  {$ifndef cgeapp}
  Forms, Controls, Graphics, Dialogs, CastleControl,
  {$else}
  CastleWindow,
  {$endif}
  CastleControls, CastleColors, CastleUIControls,
  CastleTriangles, CastleShapes, CastleVectors,
  CastleSceneCore, CastleScene, CastleTransform,
  CastleViewport, CastleCameras, CastleDownload,
  X3DNodes, X3DFields, X3DTIme, X3DLoad,
  CastleImages, CastleGLImages, CastleProjection,
  CastleTextureImages, CastleCompositeImage,
  CastleApplicationProperties, CastleLog, CastleTimeUtils, CastleKeysMouse;

type
  TImageTextureNodeArray = Array of TImageTextureNode;

  { TMultiSprit }
  TMultiSprite = class(TCastleScene)
    fAnimNode: TTimeSensorNode;
  private
    fAction: String;
    fIsLooped: Boolean; // Used in version with Notifications
    fIsPaused: Boolean; // Used in version with Notifications
    fIsPlaying: Boolean; // Used in version with Notifications
    fLastFrame: TFloatTime; // Used in version with Notifications
  public
    property  Action: String read fAction write fAction;
    property  AnimNode: TTimeSensorNode read fAnimNode write fAnimNode;
    property  IsLooped: Boolean read fIsLooped write fIsLooped;
    property  IsPaused: Boolean read fIsPaused write fIsPaused;
    property  IsPlaying: Boolean read fIsPlaying write fIsPlaying;
    procedure AddAnimation(const AAction: String; const ASensor: TTimeSensorNode; const AIsLooped: Boolean = True);
    procedure GoToFrame(AFrame: TFloatTime; const APause: Boolean = True);
    procedure Pause;
    procedure RemoveAnimation;
    procedure Start;
    procedure Stop;
  end;

  { TCastleApp }

  TCastleApp = class(TUIState)
    procedure BeforeRender; override; // TCastleUserInterface
    procedure Render; override; // TCastleUserInterface
    procedure Resize; override; // TCastleUserInterface
    procedure Update(const SecondsPassed: Single; var HandleInput: boolean); override; // TUIState
    function  Motion(const Event: TInputMotion): Boolean; override; // TUIState
    function  Press(const Event: TInputPressRelease): Boolean; override; // TUIState
    function  Release(const Event: TInputPressRelease): Boolean; override; // TUIState
  private
    Viewport: TCastleViewport;
    LabelFPS: TCastleLabel;
    LabelSprite: TCastleLabel;
    LabelResize: TCastleLabel;
    LabelSize: TCastleLabel;
    LabelRender: TCastleLabel;
  public
    SpriteSet: array of TMultiSprite;
    Stage: TCastleScene;
    gScale: Single;
    gLimit: Integer;
    gOldWidth: Single;
    gOldHeight: Single;
    procedure BootStrap;
    procedure CreateLabel(var objLabel: TCastleLabel; const Line: Integer; const BottomUp: Boolean = True);
    procedure Start; override; // TUIState
    procedure Stop; override; // TUIState
    procedure LoadViewport;
    procedure LoadModel(filenames: TStringArray; const ALimit: Integer = 0);
    procedure ScaleSheet;
  end;

var
  PrepDone: Boolean;
  CastleApp: TCastleApp;
  RenderReady: Boolean;

const
  TextureAtlas: TStringArray =
  ('castle-data:/character_demo_map_1.starling-xml', // 168
   'castle-data:/character_demo_map_2.starling-xml', // 232
   'castle-data:/character_demo_map_3.starling-xml', // 200
   'castle-data:/character_demo_map_4.starling-xml' //  80
  );

implementation
{$ifdef cgeapp}
uses AppInitialization;
{$else}
uses GUIInitialization;
{$endif}

procedure TMultiSprite.AddAnimation(const AAction: String; const ASensor: TTimeSensorNode; const AIsLooped: Boolean = True);
begin
  fAnimNode := ASensor;
  fIsLooped := AIsLooped;
  fAction := AAction;
end;

procedure TMultiSprite.GoToFrame(AFrame: TFloatTime; const APause: Boolean = True);
begin
  if not(fAnimNode = nil) then
    begin
      if ((AFrame >= 0) and (AFrame <= fAnimNode.CycleInterval)) then
        begin
          fIsPaused := False;
          fAnimNode.Stop;
          if not APause then
            begin
              fAnimNode.Start(False, True, AFrame);
              WriteLnLog('Goto (Immediate) : ' + FloatToStr(AFrame) + ' (' + FloatToStr(fAnimNode.ElapsedTimeInCycle) + ')');
            end
          else
            begin
              fIsPaused := True;
              WriteLnLog('Goto (Pause) : ' + FloatToStr(AFrame));
            end;
          fLastFrame := AFrame;
        end;
    end;
end;

procedure TMultiSprite.Pause;
begin
  fIsPaused := True;
  fLastFrame := fAnimNode.ElapsedTimeInCycle;
  fAnimNode.Stop;
end;

procedure TMultiSprite.RemoveAnimation;
begin
  fIsLooped := False;
  fIsPaused := False;
  fIsPlaying := False;
  fAction := EmptyStr;
end;

procedure TMultiSprite.Start;
begin
  fIsPaused := False;
  fAnimNode.Start(fIsLooped, True);
end;

procedure TMultiSprite.Stop;
begin
  fIsPaused := False;
  fAnimNode.Stop;
end;

procedure TCastleApp.BootStrap;
begin
  LoadModel(TextureAtlas, gLimit);
end;

procedure TCastleApp.CreateLabel(var objLabel: TCastleLabel; const Line: Integer; const BottomUp: Boolean = True);
begin
  objLabel := TCastleLabel.Create(Application);
  objLabel.Padding := 5;
  objLabel.Color := White;
  objLabel.Frame := True;
  objLabel.FrameColor := Black;
  objLabel.Anchor(hpLeft, 10);
  if BottomUp then
    objLabel.Anchor(vpBottom, 10 + (Line * 35))
  else
    objLabel.Anchor(vpTop, -(10 + (Line * 35)));
  InsertFront(objLabel);
end;

procedure TCastleApp.LoadViewport;
begin
  Viewport := TCastleViewport.Create(Application);
  Viewport.FullSize := true;
  Viewport.Camera.Orthographic.Origin := Vector2(0, 0);
  Viewport.Camera.ProjectionType := ptOrthographic;
  Viewport.Setup2D;
  Viewport.AutoCamera := False;
  Viewport.AutoNavigation := False;

  InsertFront(Viewport);

  CreateLabel(LabelResize, 0, False);
  CreateLabel(LabelSize, 1, False);

  CreateLabel(LabelSprite, 2);
  CreateLabel(LabelFPS, 1);
  CreateLabel(LabelRender, 0);
end;

procedure TCastleApp.LoadModel(filenames: TStringArray; const ALimit: Integer = 0);
var
  ModelFile: Integer;
  Model: TCastleScene;
  ASensor: TTimeSensorNode;
  WWidth: Single;
  xloc: Integer;
  yloc: Integer;
  xoff: Integer;
  yoff: Integer;
  filename: String;
  SpriteLow: Integer;
  SpriteIndex: Integer;
  ModelIndex: Integer;
  ModelCount: Integer;
begin
  WWidth := Viewport.Camera.Orthographic.EffectiveWidth;
  if Length(filenames) > 0 then
    begin
      try
        Stage := TCastleScene.Create(nil);
        Model := TMultiSprite.Create(Application);

        for ModelFile := 0 to Length(filenames) - 1 do
          begin
            filename := filenames[ModelFile];
            Model.Load(filename);

            SpriteLow := Length(SpriteSet);
            if ALimit > 0 then
              begin
                if SpriteLow >= Alimit then
                  Continue;
                ModelCount := Model.AnimationsList.Count;
                if (SpriteLow + ModelCount) > Alimit then
                  ModelCount := Alimit - SpriteLow;
              end
            else
              ModelCount := Model.AnimationsList.Count;
            SetLength(SpriteSet, SpriteLow + ModelCount);

            for ModelIndex := 0 to ModelCount - 1 do
              begin
                SpriteIndex := SpriteLow + ModelIndex;

                SpriteSet[SpriteIndex] := Model.Clone(Application) as TMultiSprite;
                SpriteSet[SpriteIndex].RenderOptions.MinificationFilter := minNearest;
                SpriteSet[SpriteIndex].RenderOptions.MagnificationFilter := magNearest;
                SpriteSet[SpriteIndex].Setup2D;
                SpriteSet[SpriteIndex].ProcessEvents := True;
                SpriteSet[SpriteIndex].AnimateOnlyWhenVisible := true;

                ASensor := SpriteSet[SpriteIndex].AnimationTimeSensor(ModelIndex);
                SpriteSet[SpriteIndex].AddAnimation(ASensor.X3DName, ASensor, True);

                SpriteSet[SpriteIndex].Scale := Vector3(gScale, gScale, gScale);

                yloc := SpriteIndex div Trunc(WWidth / SpriteSet[SpriteIndex].BoundingBox.SizeX);
                xloc := (SpriteIndex - (yloc * Trunc(WWidth / SpriteSet[SpriteIndex].BoundingBox.SizeX)));

                xoff := Trunc((SpriteSet[SpriteIndex].BoundingBox.SizeX + 1) / 2);
                yoff := Trunc((SpriteSet[SpriteIndex].BoundingBox.SizeX + 1) / 2);

                SpriteSet[SpriteIndex].Translation := Vector3(
                  (xloc * SpriteSet[SpriteIndex].BoundingBox.SizeX) + xoff,
                  (yloc * SpriteSet[SpriteIndex].BoundingBox.SizeY) + yoff,
                  0);

                SpriteSet[SpriteIndex].Start;

                Stage.Add(SpriteSet[SpriteIndex]);
              end;
          end;

        Model.Free;

        Stage.RenderOptions.MinificationFilter := minNearest;
        Stage.RenderOptions.MagnificationFilter := magNearest;
        Stage.Setup2D;
        Stage.OwnsRootNode := True;
        Stage.ProcessEvents := True;
        DynamicBatching := True;

        Viewport.Items.Add(Stage);
        Viewport.Items.MainScene := Stage;

      except
        on E : Exception do
          begin
            WriteLnLog('Oops #1' + LineEnding + E.ClassName + LineEnding + E.Message);
           end;
      end;
    end;
end;

procedure TCastleApp.Start;
begin
  inherited;
  LogTextureCache := True;

  gScale := 0.3375;
  gOldWidth := 0;
  gOldHeight := 0;
  gLimit := 680;
  SpriteSet := nil;
  LoadViewport;
  PrepDone := True;
end;

procedure TCastleApp.Stop;
begin
  inherited;
end;

procedure TCastleApp.BeforeRender;
begin
  inherited;
  if((gOldWidth <> Viewport.Camera.Orthographic.EffectiveWidth) or
     (gOldHeight <> Viewport.Camera.Orthographic.EffectiveHeight)) then
    begin
      gOldWidth := Viewport.Camera.Orthographic.EffectiveWidth;
      gOldHeight := Viewport.Camera.Orthographic.EffectiveHeight;
      Resize;
    end;
  LabelFPS.Caption := 'FPS = ' + FormatFloat('####0.00', Container.Fps.RealFps);
  LabelRender.Caption := 'Render = ' + FormatFloat('####0.00', Container.Fps.OnlyRenderFps);

  if not(Length(SpriteSet) = 0) then
    begin
      LabelSprite.Caption := 'Sprite = ' +
        FormatFloat('####0', SpriteSet[0].BoundingBox.SizeX) +
        ' x ' +
        FormatFloat('####0', SpriteSet[0].BoundingBox.SizeY);

      LabelSize.Caption := 'Size : ' +
        Container.Width.ToString + ' x ' +
        Container.Height.ToString + ' (' +
        Viewport.Camera.Orthographic.EffectiveWidth.ToString + ' x ' +
        Viewport.Camera.Orthographic.EffectiveHeight.ToString + ')';
    end;
end;

procedure TCastleApp.Render;
begin
  inherited;

  if PrepDone and GLInitialized and RenderReady then
    begin
      PrepDone := False;
      BootStrap;
    end;
  RenderReady := True;
end;

procedure TCastleApp.ScaleSheet;
var
  i: Integer;
begin
  for i := 0 to Length(SpriteSet) - 1 do
    begin
      SpriteSet[i].Scale := Vector3(gScale, gScale, gScale);
    end;

  Resize;
end;

procedure TCastleApp.Resize;
var
  i: Integer;
  WWidth: Single;
  xloc: Integer;
  yloc: Integer;
  xoff: Integer;
  yoff: Integer;
begin
  inherited;
  if Length(SpriteSet) > 0 then
    begin
      LabelResize.Caption := 'Resized : ' +
        FloatToStr(Viewport.Camera.Orthographic.EffectiveWidth) +
        ' x ' +
        FloatToStr(Viewport.Camera.Orthographic.EffectiveHeight);

      WWidth := Viewport.Camera.Orthographic.EffectiveWidth;
      for i := 0 to Length(SpriteSet) - 1 do
        begin
          yloc := i div Trunc(WWidth / SpriteSet[i].BoundingBox.SizeX);
          xloc := (i - (yloc * Trunc(WWidth / SpriteSet[i].BoundingBox.SizeX)));
          xoff := Trunc((SpriteSet[i].BoundingBox.SizeX + 1) / 2);
          yoff := Trunc((SpriteSet[i].BoundingBox.SizeX + 1) / 2);
          SpriteSet[i].Translation := Vector3(
            (xloc * SpriteSet[i].BoundingBox.SizeX) + xoff,
            (yloc * SpriteSet[i].BoundingBox.SizeY) + yoff,
            0);
        end;
    end;
end;

procedure TCastleApp.Update(const SecondsPassed: Single; var HandleInput: boolean);
begin
  inherited;
end;

function TCastleApp.Motion(const Event: TInputMotion): Boolean;
begin
  Result := inherited;
end;

function TCastleApp.Press(const Event: TInputPressRelease): Boolean;
begin
  if Event.Key = keyEscape then
    begin
      Application.Terminate;
    end;

  if Event.Key = key1 then
    begin
      gScale := 1;
      ScaleSheet;
    end;

  if Event.Key = keyS then
    begin
      Container.SaveScreen('castle-data:/screengrab.jpg');
    end;

  if Event.Key = keyArrowUp then
    begin
      gScale *= 1.1;
      ScaleSheet;
    end;

  if Event.Key = keyArrowDown then
    begin
      gScale /= 1.1;
      ScaleSheet;
    end;

  Result := inherited;
end;

function TCastleApp.Release(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
end;

end.

