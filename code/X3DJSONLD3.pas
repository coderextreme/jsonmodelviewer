unit X3DJSONLD3;

{
  Copyright (c) 2022. John Carlson
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice, this
    list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

  * Neither the name of content nor the names of its
    contributors may be used to endorse or promote products derived from
    this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE
}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, 
  CastleImages, CastleUriUtils,
  CastleInternalNodesUnsupported,
  CastleVectors,
  CastleStringUtils,
  CastleComponentSerialize, CastleScene,
  Generics.Collections, StrUtils, CastleLog, X3DLoad, X3DNodes,
  CastleRenderOptions, X3DFields;

type
  ProtoDictionary = {$ifdef FPC}specialize{$endif} TDictionary<String, TJSONObject>;
  X3DNodeDictionary = {$ifdef FPC}specialize{$endif} TDictionary<String, TX3DNodeClass>;
  X3DFieldDictionary = {$ifdef FPC}specialize{$endif} TDictionary<String, TX3DFieldClass>;

type
  TX3DJSONLD = class
  private
    x3dTidy: Boolean;
    scene: TCastleScene;
    protos: ProtoDictionary;
    builtins: TStringList;
    
    function StripQuotes(value: String): String;
    procedure InitializeBuiltins;
    function DocumentCreateComment(const arr: String): TX3DNode;
    function CommentString(const str: String): String;
    function NavigationInfoTypeToAttributeValue(const str: String): TJSONString;
    
    function CreateElement(root: TX3DRootNode; const key: String; 
      const containerField: String; obj: TJSONObject): TX3DNode;
    function getKey(originalKey: String): String;

    function DocumentCreateElement(const key: String): TX3DNode;
    
    procedure CDATACreateFunction(root: TX3DRootNode; element: TX3DNode; const value: TJSONArray; const typ: TJSONString);
    
    procedure ConvertProperty(root: TX3DRootNode; const key: String; 
      obj: TJSONObject; element: TX3DNode; const containerField: String);
    
    procedure ConvertJsonObject(root: TX3DRootNode; obj: TJSONObject; 
      const parentkey: String; element: TX3DNode; const containerField: String);
    
    procedure ConvertJsonArray(root: TX3DRootNode; arr: TJSONArray; 
      const parentkey: String; element: TX3DNode; const containerField: String);
    
    function ConvertJsonValue(root: TX3DRootNode; value: TJSONData; 
      const parentkey: String; element: TX3DNode; const containerField: String): TX3DNode;
    procedure AddChild(parentNode: TX3DNode; childNode: TX3DNode) overload; 

    function GetField(element: TX3DNode; const key: String): TX3DField;
    procedure SetBoolField(field: TSFBool; const value: TJSONBoolean); overload;
    procedure SetInt32Field(field: TSFInt32; const value: TJSONIntegerNumber); overload;
    procedure SetTimeField(field: TSFTime; const value: TJSONIntegerNumber); overload;
    procedure SetFloatField(field: TSFFloat; const value: TJSONFloatNumber); overload;
    procedure SetDoubleField(field: TSFDouble; const value: TJSONNumber); overload;
    procedure SetInt64Field(field: TSFInt32; const value: TJSONInt64Number); overload;
    procedure SetStringField(field: TSFString; const value: TJSONString); overload;
    procedure SetArrayField(field: TX3DField; const value: TJSONArray); overload;
    procedure SetNodeField(field: TSFNode; const value: TJSONObject); overload;
    procedure SetField(root: TX3DRootNode; element: TX3DNode; const key: String; const value: TJSONData); overload;
    function JSONArrayToImage(const valueArray: TJSONArray): TCastleImage;

    
  public
    class var localJSON: TX3DJSONLD;
    class var fieldFactoryMap: X3DFieldDictionary;
    class var nodeFactoryMap: X3DNodeDictionary;
    constructor Create(SceneMain: TCastleScene);
    destructor Destroy; override;
    procedure RegisterJSON;
    function LoadJsonIntoDocument(jsobj: TJSONObject; const version: String; x3dTidyFlag: Boolean): TX3DRootNode;
    function ReadJsonFile(const filename: String): TJSONObject;
    function GetX3DVersion(jsobj: TJSONObject): String;
    procedure Factory;
  end;

implementation

type
  TCrackerGrayscaleImage = class(TGrayscaleImage);
  TCrackerGrayscaleAlphaImage = class(TGrayscaleAlphaImage);
  TCrackerRGBImage = class(TRGBImage);
  TCrackerRGBAlphaImage = class(TRGBAlphaImage);

constructor TX3DJSONLD.Create(SceneMain: TCastleScene);
begin
  inherited Create;
  x3dTidy := False;
  localJSON := Self;
  scene := SceneMain;
  protos := ProtoDictionary.Create;
  builtins := TStringList.Create;
  builtins.Sorted := True;
  builtins.Duplicates := dupIgnore;
  nodeFactoryMap := X3DNodeDictionary.Create; 
  fieldFactoryMap := X3DFieldDictionary.Create; 
  Factory;
  InitializeBuiltins;
end;

destructor TX3DJSONLD.Destroy;
begin
  protos.Free;
  builtins.Free;
  inherited Destroy;
end;

function TX3DJSONLD.StripQuotes(value: String): String;
begin
	{
  // CastleLog.WriteLnLog('stripping '+value);
  if (Length(value) >= 2) and (value[1] = '"') and (value[Length(value)] = '"') then begin
    Result := Copy(value, 2, Length(value) - 2);
    // CastleLog.WriteLnLog('stripped1 '+Result);
  end else begin }
    Result := value;
    {
    // CastleLog.WriteLnLog('stripped2 '+Result);
  end;
  }
end;

procedure TX3DJSONLD.InitializeBuiltins;
begin
  { X3D abstract node types }
  builtins.Add('X3DAppearanceChildNode');
  builtins.Add('X3DAppearanceNode');
  builtins.Add('X3DArrayField');
  builtins.Add('X3DBackgroundNode');
  builtins.Add('X3DBindableNode');
  builtins.Add('X3DChaserNode');
  builtins.Add('X3DChildNode');
  builtins.Add('X3DColorNode');
  builtins.Add('X3DComposableVolumeRenderStyleNode');
  builtins.Add('X3DComposedGeometryNode');
  builtins.Add('X3DCoordinateNode');
  builtins.Add('X3DDamperNode');
  builtins.Add('X3DDragSensorNode');
  builtins.Add('X3DEnvironmentalSensorNode');
  builtins.Add('X3DEnvironmentTextureNode');
  builtins.Add('X3DField');
  builtins.Add('X3DFollowerNode');
  builtins.Add('X3DFontStyleNode');
  builtins.Add('X3DGeometricPropertyNode');
  builtins.Add('X3DGeometryNode');
  builtins.Add('X3DGroupingNode');
  builtins.Add('X3DInfoNode');
  builtins.Add('X3DInterpolatorNode');
  builtins.Add('X3DKeyDeviceSensorNode');
  builtins.Add('X3DLayerNode');
  builtins.Add('X3DLayoutNode');
  builtins.Add('X3DLightNode');
  builtins.Add('X3DMaterialNode');
  builtins.Add('X3DNBodyCollidableNode');
  builtins.Add('X3DNBodyCollisionSpaceNode');
  builtins.Add('X3DNetworkSensorNode');
  builtins.Add('X3DNode');
  builtins.Add('X3DNormalNode');
  builtins.Add('X3DNurbsControlCurveNode');
  builtins.Add('X3DNurbsSurfaceGeometryNode');
  builtins.Add('X3DOneSidedMaterialNode');
  builtins.Add('X3DParametricGeometryNode');
  builtins.Add('X3DParticleEmitterNode');
  builtins.Add('X3DParticlePhysicsModelNode');
  builtins.Add('X3DPickSensorNode');
  builtins.Add('X3DPointingDeviceSensorNode');
  builtins.Add('X3DProductStructureChildNode');
  builtins.Add('X3DPrototypeInstance');
  builtins.Add('X3DRigidJointNode');
  builtins.Add('X3DScriptNode');
  builtins.Add('X3DSensorNode');
  builtins.Add('X3DSequencerNode');
  builtins.Add('X3DShaderNode');
  builtins.Add('X3DShapeNode');
  builtins.Add('X3DSingleTextureCoordinateNode');
  builtins.Add('X3DSingleTextureNode');
  builtins.Add('X3DSingleTextureTransformNode');
  builtins.Add('X3DSoundChannelNode');
  builtins.Add('X3DSoundDestinationNode');
  builtins.Add('X3DSoundNode');
  builtins.Add('X3DSoundProcessingNode');
  builtins.Add('X3DSoundSourceNode');
  builtins.Add('X3DStatement');
  builtins.Add('X3DTexture2DNode');
  builtins.Add('X3DTexture3DNode');
  builtins.Add('X3DTextureCoordinateNode');
  builtins.Add('X3DTextureNode');
  builtins.Add('X3DTextureProjectorNode');
  builtins.Add('X3DTextureTransformNode');
  builtins.Add('X3DTimeDependentNode');
  builtins.Add('X3DTouchSensorNode');
  builtins.Add('X3DTriggerNode');
  builtins.Add('X3DVertexAttributeNode');
  builtins.Add('X3DViewpointNode');
  builtins.Add('X3DViewportNode');
  builtins.Add('X3DVolumeDataNode');
  builtins.Add('X3DVolumeRenderStyleNode');
  builtins.Add('X3DMaterialExtensionNode');
  builtins.Add('X3DBoundedObject');
  builtins.Add('X3DFogObject');
  builtins.Add('X3DMetadataObject');
  builtins.Add('X3DPickableObject');
  builtins.Add('X3DProgrammableShaderObject');
  builtins.Add('X3DUrlObject');
  
  { X3D concrete node types }
  builtins.Add('AcousticProperties');
  builtins.Add('Analyser');
  builtins.Add('Anchor');
  builtins.Add('Appearance');
  builtins.Add('Arc2D');
  builtins.Add('ArcClose2D');
  builtins.Add('AudioClip');
  builtins.Add('AudioDestination');
  builtins.Add('Background');
  builtins.Add('BallJoint');
  builtins.Add('Billboard');
  builtins.Add('BiquadFilter');
  builtins.Add('BlendedVolumeStyle');
  builtins.Add('BooleanFilter');
  builtins.Add('BooleanSequencer');
  builtins.Add('BooleanToggle');
  builtins.Add('BooleanTrigger');
  builtins.Add('BoundaryEnhancementVolumeStyle');
  builtins.Add('BoundedPhysicsModel');
  builtins.Add('Box');
  builtins.Add('BufferAudioSource');
  builtins.Add('CADAssembly');
  builtins.Add('CADFace');
  builtins.Add('CADLayer');
  builtins.Add('CADPart');
  builtins.Add('CartoonVolumeStyle');
  builtins.Add('ChannelMerger');
  builtins.Add('ChannelSelector');
  builtins.Add('ChannelSplitter');
  builtins.Add('Circle2D');
  builtins.Add('ClipPlane');
  builtins.Add('CollidableOffset');
  builtins.Add('CollidableShape');
  builtins.Add('Collision');
  builtins.Add('CollisionCollection');
  builtins.Add('CollisionSensor');
  builtins.Add('CollisionSpace');
  builtins.Add('Color');
  builtins.Add('ColorChaser');
  builtins.Add('ColorDamper');
  builtins.Add('ColorInterpolator');
  builtins.Add('ColorRGBA');
  builtins.Add('ComposedCubeMapTexture');
  builtins.Add('ComposedShader');
  builtins.Add('ComposedTexture3D');
  builtins.Add('ComposedVolumeStyle');
  builtins.Add('Cone');
  builtins.Add('ConeEmitter');
  builtins.Add('Contact');
  builtins.Add('Contour2D');
  builtins.Add('ContourPolyline2D');
  builtins.Add('Convolver');
  builtins.Add('Coordinate');
  builtins.Add('CoordinateChaser');
  builtins.Add('CoordinateDamper');
  builtins.Add('CoordinateDouble');
  builtins.Add('CoordinateInterpolator');
  builtins.Add('CoordinateInterpolator2D');
  builtins.Add('Cylinder');
  builtins.Add('CylinderSensor');
  builtins.Add('Delay');
  builtins.Add('DirectionalLight');
  builtins.Add('DISEntityManager');
  builtins.Add('DISEntityTypeMapping');
  builtins.Add('Disk2D');
  builtins.Add('DoubleAxisHingeJoint');
  builtins.Add('DynamicsCompressor');
  builtins.Add('EaseInEaseOut');
  builtins.Add('EdgeEnhancementVolumeStyle');
  builtins.Add('ElevationGrid');
  builtins.Add('EspduTransform');
  builtins.Add('ExplosionEmitter');
  builtins.Add('Extrusion');
  builtins.Add('FillProperties');
  builtins.Add('FloatVertexAttribute');
  builtins.Add('Fog');
  builtins.Add('FogCoordinate');
  builtins.Add('FontStyle');
  builtins.Add('ForcePhysicsModel');
  builtins.Add('Gain');
  builtins.Add('GeneratedCubeMapTexture');
  builtins.Add('GeoCoordinate');
  builtins.Add('GeoElevationGrid');
  builtins.Add('GeoLocation');
  builtins.Add('GeoLOD');
  builtins.Add('GeoMetadata');
  builtins.Add('GeoOrigin');
  builtins.Add('GeoPositionInterpolator');
  builtins.Add('GeoProximitySensor');
  builtins.Add('GeoTouchSensor');
  builtins.Add('GeoTransform');
  builtins.Add('GeoViewpoint');
  builtins.Add('Group');
  builtins.Add('HAnimDisplacer');
  builtins.Add('HAnimHumanoid');
  builtins.Add('HAnimJoint');
  builtins.Add('HAnimMotion');
  builtins.Add('HAnimSegment');
  builtins.Add('HAnimSite');
  builtins.Add('ImageCubeMapTexture');
  builtins.Add('ImageTexture');
  builtins.Add('ImageTexture3D');
  builtins.Add('IndexedFaceSet');
  builtins.Add('IndexedLineSet');
  builtins.Add('IndexedQuadSet');
  builtins.Add('IndexedTriangleFanSet');
  builtins.Add('IndexedTriangleSet');
  builtins.Add('IndexedTriangleStripSet');
  builtins.Add('Inline');
  builtins.Add('IntegerSequencer');
  builtins.Add('IntegerTrigger');
  builtins.Add('IsoSurfaceVolumeData');
  builtins.Add('KeySensor');
  builtins.Add('Layer');
  builtins.Add('LayerSet');
  builtins.Add('Layout');
  builtins.Add('LayoutGroup');
  builtins.Add('LayoutLayer');
  builtins.Add('LinePickSensor');
  builtins.Add('LineProperties');
  builtins.Add('LineSet');
  builtins.Add('ListenerPointSource');
  builtins.Add('LoadSensor');
  builtins.Add('LocalFog');
  builtins.Add('LOD');
  builtins.Add('Material');
  builtins.Add('Matrix3VertexAttribute');
  builtins.Add('Matrix4VertexAttribute');
  builtins.Add('MetadataBoolean');
  builtins.Add('MetadataDouble');
  builtins.Add('MetadataFloat');
  builtins.Add('MetadataInteger');
  builtins.Add('MetadataSet');
  builtins.Add('MetadataString');
  builtins.Add('MicrophoneSource');
  builtins.Add('MotorJoint');
  builtins.Add('MovieTexture');
  builtins.Add('MultiTexture');
  builtins.Add('MultiTextureCoordinate');
  builtins.Add('MultiTextureTransform');
  builtins.Add('NavigationInfo');
  builtins.Add('Normal');
  builtins.Add('NormalInterpolator');
  builtins.Add('NurbsCurve');
  builtins.Add('NurbsCurve2D');
  builtins.Add('NurbsOrientationInterpolator');
  builtins.Add('NurbsPatchSurface');
  builtins.Add('NurbsPositionInterpolator');
  builtins.Add('NurbsSet');
  builtins.Add('NurbsSurfaceInterpolator');
  builtins.Add('NurbsSweptSurface');
  builtins.Add('NurbsSwungSurface');
  builtins.Add('NurbsTextureCoordinate');
  builtins.Add('NurbsTrimmedSurface');
  builtins.Add('OpacityMapVolumeStyle');
  builtins.Add('OrientationChaser');
  builtins.Add('OrientationDamper');
  builtins.Add('OrientationInterpolator');
  builtins.Add('OrthoViewpoint');
  builtins.Add('OscillatorSource');
  builtins.Add('PackagedShader');
  builtins.Add('ParticleSystem');
  builtins.Add('PeriodicWave');
  builtins.Add('PhysicalMaterial');
  builtins.Add('PickableGroup');
  builtins.Add('PixelTexture');
  builtins.Add('PixelTexture3D');
  builtins.Add('PlaneSensor');
  builtins.Add('PointEmitter');
  builtins.Add('PointLight');
  builtins.Add('PointPickSensor');
  builtins.Add('PointProperties');
  builtins.Add('PointSet');
  builtins.Add('Polyline2D');
  builtins.Add('PolylineEmitter');
  builtins.Add('Polypoint2D');
  builtins.Add('PositionChaser');
  builtins.Add('PositionChaser2D');
  builtins.Add('PositionDamper');
  builtins.Add('PositionDamper2D');
  builtins.Add('PositionInterpolator');
  builtins.Add('PositionInterpolator2D');
  builtins.Add('PrimitivePickSensor');
  builtins.Add('ProgramShader');
  builtins.Add('ProjectionVolumeStyle');
  builtins.Add('ProtoInstance');
  builtins.Add('ProximitySensor');
  builtins.Add('QuadSet');
  builtins.Add('ReceiverPdu');
  builtins.Add('Rectangle2D');
  builtins.Add('RigidBody');
  builtins.Add('RigidBodyCollection');
  builtins.Add('ScalarChaser');
  builtins.Add('ScalarDamper');
  builtins.Add('ScalarInterpolator');
  builtins.Add('ScreenFontStyle');
  builtins.Add('ScreenGroup');
  builtins.Add('Script');
  builtins.Add('SegmentedVolumeData');
  builtins.Add('ShadedVolumeStyle');
  builtins.Add('ShaderPart');
  builtins.Add('ShaderProgram');
  builtins.Add('Shape');
  builtins.Add('SignalPdu');
  builtins.Add('SilhouetteEnhancementVolumeStyle');
  builtins.Add('SingleAxisHingeJoint');
  builtins.Add('SliderJoint');
  builtins.Add('Sound');
  builtins.Add('SpatialSound');
  builtins.Add('Sphere');
  builtins.Add('SphereSensor');
  builtins.Add('SplinePositionInterpolator');
  builtins.Add('SplinePositionInterpolator2D');
  builtins.Add('SplineScalarInterpolator');
  builtins.Add('SpotLight');
  builtins.Add('SquadOrientationInterpolator');
  builtins.Add('StaticGroup');
  builtins.Add('StreamAudioDestination');
  builtins.Add('StreamAudioSource');
  builtins.Add('StringSensor');
  builtins.Add('SurfaceEmitter');
  builtins.Add('Switch');
  builtins.Add('TexCoordChaser2D');
  builtins.Add('TexCoordDamper2D');
  builtins.Add('Text');
  builtins.Add('TextureBackground');
  builtins.Add('TextureCoordinate');
  builtins.Add('TextureCoordinate3D');
  builtins.Add('TextureCoordinate4D');
  builtins.Add('TextureCoordinateGenerator');
  builtins.Add('TextureProjector');
  builtins.Add('TextureProjectorParallel');
  builtins.Add('TextureProperties');
  builtins.Add('TextureTransform');
  builtins.Add('TextureTransform3D');
  builtins.Add('TextureTransformMatrix3D');
  builtins.Add('TimeSensor');
  builtins.Add('TimeTrigger');
  builtins.Add('ToneMappedVolumeStyle');
  builtins.Add('TouchSensor');
  builtins.Add('Transform');
  builtins.Add('TransformSensor');
  builtins.Add('TransmitterPdu');
  builtins.Add('TriangleFanSet');
  builtins.Add('TriangleSet');
  builtins.Add('TriangleSet2D');
  builtins.Add('TriangleStripSet');
  builtins.Add('TwoSidedMaterial');
  builtins.Add('UniversalJoint');
  builtins.Add('UnlitMaterial');
  builtins.Add('Viewpoint');
  builtins.Add('ViewpointGroup');
  builtins.Add('Viewport');
  builtins.Add('VisibilitySensor');
  builtins.Add('VolumeData');
  builtins.Add('VolumeEmitter');
  builtins.Add('VolumePickSensor');
  builtins.Add('WaveShaper');
  builtins.Add('WindPhysicsModel');
  builtins.Add('WorldInfo');
  builtins.Add('EnvironmentLight');
  builtins.Add('Tangent');
  builtins.Add('ImageTextureAtlas');
  builtins.Add('AnisotropyMaterialExtension');
  builtins.Add('BlendMode');
  builtins.Add('ClearcoatMaterialExtension');
  builtins.Add('DepthMode');
  builtins.Add('DispersionMaterialExtension');
  builtins.Add('EmissiveStrengthMaterialExtension');
  builtins.Add('IORMaterialExtension');
  builtins.Add('InstancedShape');
  builtins.Add('IridescenceMaterialExtension');
  builtins.Add('SheenMaterialExtension');
  builtins.Add('SpecularGlossinessMaterial');
  builtins.Add('SpecularMaterialExtension');
  builtins.Add('TransmissionMaterialExtension');
  builtins.Add('VolumeMaterialExtension');
  builtins.Add('DiffuseTransmissionMaterialExtension');
  
  { X3D statements }
  builtins.Add('component');
  builtins.Add('connect');
  builtins.Add('EXPORT');
  builtins.Add('ExternProtoDeclare');
  builtins.Add('field');
  builtins.Add('fieldValue');
  builtins.Add('head');
  builtins.Add('IMPORT');
  builtins.Add('IS');
  builtins.Add('meta');
  builtins.Add('ProtoBody');
  builtins.Add('ProtoDeclare');
  builtins.Add('ProtoInterface');
  builtins.Add('ROUTE');
  builtins.Add('Scene');
  builtins.Add('unit');
  builtins.Add('X3D');
  
  { X3D field types }
  builtins.Add('SFBool');
  builtins.Add('MFBool');
  builtins.Add('SFColor');
  builtins.Add('MFColor');
  builtins.Add('SFColorRGBA');
  builtins.Add('MFColorRGBA');
  builtins.Add('SFDouble');
  builtins.Add('MFDouble');
  builtins.Add('SFFloat');
  builtins.Add('MFFloat');
  builtins.Add('SFImage');
  builtins.Add('MFImage');
  builtins.Add('SFInt32');
  builtins.Add('MFInt32');
  builtins.Add('SFMatrix3d');
  builtins.Add('MFMatrix3d');
  builtins.Add('SFMatrix3f');
  builtins.Add('MFMatrix3f');
  builtins.Add('SFMatrix4d');
  builtins.Add('MFMatrix4d');
  builtins.Add('SFMatrix4f');
  builtins.Add('MFMatrix4f');
  builtins.Add('SFNode');
  builtins.Add('MFNode');
  builtins.Add('SFRotation');
  builtins.Add('MFRotation');
  builtins.Add('SFString');
  builtins.Add('MFString');
  builtins.Add('SFTime');
  builtins.Add('MFTime');
  builtins.Add('SFVec2d');
  builtins.Add('MFVec2d');
  builtins.Add('SFVec2f');
  builtins.Add('MFVec2f');
  builtins.Add('SFVec3d');
  builtins.Add('MFVec3d');
  builtins.Add('SFVec3f');
  builtins.Add('MFVec3f');
  builtins.Add('SFVec4d');
  builtins.Add('MFVec4d');
  builtins.Add('SFVec4f');
  builtins.Add('MFVec4f');
//  NodesManager.RegisterNodeClasses([
//  { TAcousticPropertiesNode, }
//  { TAnalyserNode, }
//  TAppearanceNode,
//  TArc2DNode,
//  TArcClose2DNode,
//  TAudioClipNode,
//  { TAudioDestinationNode, }
//  TBackgroundNode,
//  TBallJointNode,
//  TBillboardNode,
//  { TBiquadFilterNode, }
//  { TBlendedVolumeStyleNode, }
//  TBooleanFilterNode,
//  TBooleanSequencerNode,
//  TBooleanToggleNode,
//  TBooleanTriggerNode,
//  { TBoundaryEnhancementVolumeStyleNode, }
//  TBoundedPhysicsModelNode,
//  TBoxNode,
//  { TBufferAudioSourceNode, }
//  TCADAssemblyNode,
//  TCADFaceNode,
//  TCADLayerNode,
//  TCADPartNode,
//  { TCartoonVolumeStyleNode, }
//  { TChannelMergerNode, }
//  { TChannelSelectorNode, }
//  { TChannelSplitterNode, }
//  TCircle2DNode,
//  TClipPlaneNode,
//  TCollidableOffsetNode,
//  TCollidableShapeNode,
//  TCollisionNode,
//  TCollisionCollectionNode,
//  TCollisionSensorNode,
//  TCollisionSpaceNode,
//  TColorNode,
//  { TColorChaserNode, }
//  TColorDamperNode,
//  TColorInterpolatorNode,
//  TColorRGBANode,
//  TComposedCubeMapTextureNode,
//  TComposedShaderNode,
//  TComposedTexture3DNode,
//  { TComposedVolumeStyleNode, }
//  TConeNode,
//  TConeEmitterNode,
//  TContactNode,
//  TContour2DNode,
//  TContourPolyline2DNode,
//  { TConvolverNode, }
//  TCoordinateNode,
//  { TCoordinateChaserNode, }
//  TCoordinateDamperNode,
//  TCoordinateDoubleNode,
//  TCoordinateInterpolatorNode,
//  TCoordinateInterpolator2DNode,
//  TCylinderNode,
//  TCylinderSensorNode,
//  { TDelayNode, }
//  TDirectionalLightNode,
//  TDISEntityManagerNode,
//  TDISEntityTypeMappingNode,
//  TDisk2DNode,
//  TDoubleAxisHingeJointNode,
//  { TDynamicsCompressorNode, }
//  TEaseInEaseOutNode,
//  { TEdgeEnhancementVolumeStyleNode, }
//  TElevationGridNode,
//  TEspduTransformNode,
//  TExplosionEmitterNode,
//  TExtrusionNode,
//  TFillPropertiesNode,
//  TFloatVertexAttributeNode,
//  TFogNode,
//  TFogCoordinateNode,
//  TFontStyleNode,
//  TForcePhysicsModelNode,
//  { TGainNode, }
//  TGeneratedCubeMapTextureNode,
//  TGeoCoordinateNode,
//  TGeoElevationGridNode,
//  TGeoLocationNode,
//  TGeoLODNode,
//  TGeoMetadataNode,
//  TGeoOriginNode,
//  TGeoPositionInterpolatorNode,
//  TGeoProximitySensorNode,
//  TGeoTouchSensorNode,
//  TGeoTransformNode,
//  TGeoViewpointNode,
//  TGroupNode,
//  THAnimDisplacerNode,
//  THAnimHumanoidNode,
//  THAnimJointNode,
//  THAnimMotionNode,
//  THAnimSegmentNode,
//  THAnimSiteNode,
//  TImageCubeMapTextureNode,
//  TImageTextureNode,
//  TImageTexture3DNode,
//  TIndexedFaceSetNode,
//  TIndexedLineSetNode,
//  TIndexedQuadSetNode,
//  TIndexedTriangleFanSetNode,
//  TIndexedTriangleSetNode,
//  TIndexedTriangleStripSetNode,
//  TInlineNode,
//  TIntegerSequencerNode,
//  TIntegerTriggerNode,
//  { TIsoSurfaceVolumeDataNode, }
//  TKeySensorNode,
//  TLayerNode,
//  TLayerSetNode,
//  TLayoutNode,
//  TLayoutGroupNode,
//  TLayoutLayerNode,
//  TLinePickSensorNode,
//  TLinePropertiesNode,
//  TLineSetNode,
//  { TListenerPointSourceNode, }
//  TLoadSensorNode,
//  TLocalFogNode,
//  TLODNode,
//  TMaterialNode,
//  TMatrix3VertexAttributeNode,
//  TMatrix4VertexAttributeNode,
//  TMetadataBooleanNode,
//  TMetadataDoubleNode,
//  TMetadataFloatNode,
//  TMetadataIntegerNode,
//  TMetadataSetNode,
//  TMetadataStringNode,
//  { TMicrophoneSourceNode, }
//  TMotorJointNode,
//  TMovieTextureNode,
//  TMultiTextureNode,
//  TMultiTextureCoordinateNode,
//  TMultiTextureTransformNode,
//  TNavigationInfoNode,
//  TNormalNode,
//  TNormalInterpolatorNode,
//  TNurbsCurveNode,
//  TNurbsCurve2DNode,
//  TNurbsOrientationInterpolatorNode,
//  TNurbsPatchSurfaceNode,
//  TNurbsPositionInterpolatorNode,
//  TNurbsSetNode,
//  TNurbsSurfaceInterpolatorNode,
//  TNurbsSweptSurfaceNode,
//  TNurbsSwungSurfaceNode,
//  TNurbsTextureCoordinateNode,
//  TNurbsTrimmedSurfaceNode,
//  { TOpacityMapVolumeStyleNode, }
//  TOrientationChaserNode,
//  TOrientationDamperNode,
//  TOrientationInterpolatorNode,
//  TOrthoViewpointNode,
//  { TOscillatorSourceNode, }
//  TPackagedShaderNode,
//  TParticleSystemNode,
//  { TPeriodicWaveNode, }
//  TPhysicalMaterialNode,
//  TPickableGroupNode,
//  TPixelTextureNode,
//  TPixelTexture3DNode,
//  TPlaneSensorNode,
//  TPointEmitterNode,
//  TPointLightNode,
//  TPointPickSensorNode,
//  { TPointPropertiesNode, }
//  TPointSetNode,
//  TPolyline2DNode,
//  TPolylineEmitterNode,
//  TPolypoint2DNode,
//  TPositionChaserNode,
//  TPositionChaser2DNode,
//  TPositionDamperNode,
//  TPositionDamper2DNode,
//  TPositionInterpolatorNode,
//  TPositionInterpolator2DNode,
//  TPrimitivePickSensorNode,
//  TProgramShaderNode,
//  { TProjectionVolumeStyleNode, }
//  TGroupNode, { TODO fix }
//  TProximitySensorNode,
//  TQuadSetNode,
//  TReceiverPduNode,
//  TRectangle2DNode,
//  TRigidBodyNode,
//  TRigidBodyCollectionNode,
//  TScalarChaserNode,
//  { TScalarDamperNode, }
//  TScalarInterpolatorNode,
//  TScreenFontStyleNode,
//  TScreenGroupNode,
//  TScriptNode,
//  { TSegmentedVolumeDataNode, }
//  { TShadedVolumeStyleNode, }
//  TShaderPartNode,
//  TShaderProgramNode,
//  TShapeNode,
//  TSignalPduNode,
//  { TSilhouetteEnhancementVolumeStyleNode, }
//  TSingleAxisHingeJointNode,
//  TSliderJointNode,
//  TSoundNode,
//  { TSpatialSoundNode, }
//  TSphereNode,
//  TSphereSensorNode,
//  TSplinePositionInterpolatorNode,
//  TSplinePositionInterpolator2DNode,
//  TSplineScalarInterpolatorNode,
//  TSpotLightNode,
//  TSquadOrientationInterpolatorNode,
//  TStaticGroupNode,
//  { TStreamAudioDestinationNode, }
//  { TStreamAudioSourceNode, }
//  TStringSensorNode,
//  TSurfaceEmitterNode,
//  TSwitchNode,
//  { TTexCoordChaser2DNode, }
//  { TTexCoordDamper2DNode, }
//  TTextNode,
//  TTextureBackgroundNode,
//  TTextureCoordinateNode,
//  TTextureCoordinate3DNode,
//  TTextureCoordinate4DNode,
//  TTextureCoordinateGeneratorNode,
//  TTextureProjectorNode,
//  TTextureProjectorParallelNode,
//  TTexturePropertiesNode,
//  TTextureTransformNode,
//  TTextureTransform3DNode,
//  TTextureTransformMatrix3DNode,
//  TTimeSensorNode,
//  TTimeTriggerNode,
//  { TToneMappedVolumeStyleNode, }
//  TTouchSensorNode,
//  TTransformNode,
//  TTransformSensorNode,
//  TTransmitterPduNode,
//  TTriangleFanSetNode,
//  TTriangleSetNode,
//  TTriangleSet2DNode,
//  TTriangleStripSetNode,
//  TTwoSidedMaterialNode,
//  TUniversalJointNode,
//  TUnlitMaterialNode,
//  TViewpointNode,
//  TViewpointGroupNode,
//  TViewportNode,
//  TVisibilitySensorNode,
//  { TVolumeDataNode, }
//  TVolumeEmitterNode,
//  TVolumePickSensorNode,
//  { TWaveShaperNode, }
//  TWindPhysicsModelNode,
//  TWorldInfoNode,
//  TEnvironmentLightNode,
//  TTangentNode,
//  { TImageTextureAtlasNode, }
//  { TAnisotropyMaterialExtensionNode, }
//  { TClearcoatMaterialExtensionNode, }
//  { TDepthModeNode, }
//  { TDispersionMaterialExtensionNode, }
//  { TEmissiveStrengthMaterialExtensionNode, }
//  { TIORMaterialExtensionNode, }
//  { TInstancedShapeNode, }
//  { TIridescenceMaterialExtensionNode, }
//  { TSheenMaterialExtensionNode, }
//  { TSpecularGlossinessMaterialNode, }
//  { TSpecularMaterialExtensionNode, }
//  { TTransmissionMaterialExtensionNode, }
//  { TVolumeMaterialExtensionNode, }
//  { TDiffuseTransmissionMaterialExtensionNode, }
//  TBlendModeNode
// ]);
end;

procedure TX3DJSONLD.SetStringField(field: TSFString; const value: TJSONString) overload;
var
  valueStr: String;
begin
      valueStr := value.AsString;
      if not Assigned(field) then begin
        CastleLog.writeLnLog('ERROR', 'Field is unassigned');
      end else if (valueStr = '') then begin
        CastleLog.writeLnLog('ERROR', 'value is unassigned');
      end else begin
      	field.Value := valueStr;
        CastleLog.writeLnLog('SUCCESS', 'value is assigned to %s', [ valueStr ]);
      end;
end;

function TX3DJSONLD.GetField(element: TX3DNode; const key: String): TX3DField;
begin
    try
      Result := nil;
      if (element = nil) then begin
	CastleLog.WriteLnLog('ERROR', 'Element is nil for %s', [ key ]);
	Exit;
      end;
      if not Assigned(element) then begin
	CastleLog.WriteLnLog('ERROR', 'Element is not assigned for %s', [ key ]);
	Exit;
      end;
      if not (element is TX3DNode) then begin
	CastleLog.WriteLnLog('ERROR', 'Element is not TX3DNode for %s', [ key ]);
	Exit;
      end;
      CastleLog.WriteLnLog('DEBUG', 'class %s %s, field %s', [ element.X3DType, element.ClassName, key ]);
      Result := element.Field(key, false);
      if (Result = nil) then begin
	CastleLog.WriteLnLog('ERROR', 'Did not find key %s in class', [ key, element.ClassName ]);
      end else begin
	CastleLog.WriteLnLog('SUCCESS', 'Found field %s of class %s', [ key, Result.ClassName ]);
      end
    except
      on E: Exception do begin
        Result := nil;
        CastleLog.WriteLnLog('ERROR', 'Can not find field %s', [ key ]);
        Exit;
      end;
    end;
end;

procedure TX3DJSONLD.SetBoolField(field: TSFBool; const value: TJSONBoolean) overload;
begin
  field.Value := value.AsBoolean;
end;

procedure TX3DJSONLD.SetInt32Field(field: TSFInt32; const value: TJSONIntegerNumber); overload;
begin
      field.Value := value.AsInteger;
end;

procedure TX3DJSONLD.SetTimeField(field: TSFTime; const value: TJSONIntegerNumber); overload;  { TODO think about using 64 bit }

begin
      field.Value := value.AsInteger;
end;

procedure TX3DJSONLD.SetInt64Field(field: TSFInt32; const value: TJSONInt64Number); overload;
begin
      field.Value := value.AsInteger;
end;

procedure TX3DJSONLD.SetFloatField(field: TSFFloat; const value: TJSONFloatNumber); overload;
begin
      field.Value := value.AsFloat;
end;

procedure TX3DJSONLD.SetDoubleField(field: TSFDouble; const value: TJSONNumber); overload;
begin
  field.Value := value.AsFloat;
end;

procedure TX3DJSONLD.SetNodeField(field: TSFNode; const value: TJSONObject); overload;
begin
end;

procedure TX3DJSONLD.SetArrayField(field: TX3DField; const value: TJSONArray); overload;
var
  I: Integer;
  valueArray: TJSONArray;
  stringValueArray: TCastleStringList;
  NewMatrix3dValue: TMatrix3Double;
  NewMatrix3fValue: TMatrix3;
  NewMatrix4dValue: TMatrix4Double;
  NewMatrix4fValue: TMatrix4;
  key: String;
begin
      if (field = nil) then begin
	CastleLog.WriteLnLog('ERROR', 'Field is nil');
	Exit;
      end;
      key := field.X3DType;
      if (value = nil) then begin
	CastleLog.WriteLnLog('ERROR', 'Value is nil for %s', [ key ]);
	Exit;
      end;
      if not Assigned(value) then begin
	CastleLog.WriteLnLog('ERROR', 'Value is not assigned for %s', [ key ]);
	Exit;
      end;
      valueArray := TJSONArray(value);
	{ CastleLog.WriteLnLog('DEBUG Setting '+element.ClassName+'.'+key+' to '+WriteJSON(value));
    CastleLog.WriteLnLog('DEBUG Setting '+element.ClassName+'.'+key+' to '+value.toJSON(true)); }
    {
    if field is TMFBool then begin
	    TMFBool(field).Value := value;
    end else if field is TMFColor then begin
	    TMFColor(field).Value := value;
    end else if field is TMFColorRGBA then begin
	    TMFColorRGBA(field).Value := value;
    end else if field is TMFDouble then begin
	    TMFDouble(field).Value := value;
    end else if field is TMFFloat then begin
	    TMFFloat(field).Value := value;
    end else if field is TMFImage then begin
	    TMFImage(field).Value := value;
    end else }
    if field is TMFInt32 then begin
      TMFInt32(field).Count := valueArray.Count;
      for I := 0 to valueArray.Count - 1 do begin
      	TMFInt32(field).Items[I] := valueArray.Items[I].AsInteger;
      end;
      {
    end else if field is TMFMatrix3d then begin
	    TMFMatrix3d(field).Value := value;
    end else if field is TMFMatrix3f then begin
	    TMFMatrix3f(field).Value := value;
    end else if field is TMFMatrix4d then begin
	    TMFMatrix4d(field).Value := value;
    end else if field is TMFMatrix4f then begin
	    TMFMatrix4f(field).Value := value;
    end else if field is TMFNode then begin
	    TMFNode(field).Value := value;
    end else if field is TMFRotation then begin
	    TMFRotation(field).Value := value;
	    }
    end else if field is TMFString then begin
	    { CastleLog.writeLnLog('count is '+ IntToStr(valueArray.Count)); }
      TMFString(field).Count := valueArray.Count;
      for I := 0 to valueArray.Count - 1 do begin
	      { CastleLog.writeLnLog('index begin is '+ IntToStr(I)); }
      	TMFString(field).Items[I] := valueArray.Strings[I];
	{ CastleLog.writeLnLog('index end is '+ IntToStr(I)); }
      end;
	    {
    end else if field is TMFTime then begin
	    TMFTime(field).Value := value;
    end else if field is TMFVec2d then begin
	    TMFVec2d(field).Value := value;
    end else if field is TMFVec2f then begin
	    TMFVec2f(field).Value := value;
    }
    end else if field is TMFVec3d then begin
      for I := 0 to valueArray.Count div 3 do begin
      	TMFVec3d(field).Items[I] := Vector3Double(
	  valueArray.Floats[I*3],
	  valueArray.Floats[I*3+1],
	  valueArray.Floats[I*3+2]);
      end;
    end else if field is TMFVec3f then begin
      if valueArray.Count = 0 then begin
	for I := 0 to valueArray.Count div 3 do begin
	  TMFVec3f(field).Items[I] := Vector3(
		  valueArray.Items[I*3].AsFloat,
		  valueArray.Items[I*3+1].AsFloat,
		  valueArray.Items[I*3+2].AsFloat);
	end;
      end else begin
	CastleLog.writeLnLog('zero length MFVec3f');
      end;
	{ else if field is TMFVec4d then begin
	    TMFVec4d(field).Value := value;
    end else if field is TMFVec4f then begin
	    TMFVec4f(field).Value := value; }
    end else if (field is TSFColor) and (value is TJSONArray) then begin
      TSFColor(field).Value := Vector3(
        valueArray.Items[0].AsFloat,
        valueArray.Items[1].AsFloat,
        valueArray.Items[2].AsFloat);
    end else if (field is TSFColorRGBA) and (value is TJSONArray) then begin
      TSFColorRGBA(field).Value := Vector4(
        valueArray.Items[0].AsFloat,
        valueArray.Items[1].AsFloat,
        valueArray.Items[2].AsFloat,
        valueArray.Items[3].AsFloat);
    end else if (field is TSFImage) and (key = 'image') and (value is TJSONArray) then begin
      TSFImage(field).Value := JSONArrayToImage(valueArray);
    end else if (field is TSFImage) and (key = 'url') and (value is TJSONArray) then begin
      raise Exception.Create('Image URLs not handled');
    end else if (field is TSFMatrix3d) and (value is TJSONArray) then begin
      if valueArray.Count < 9 then
        raise Exception.Create('Matrix array must have 9 elements');
      NewMatrix3dValue := TMatrix3Double.Identity;
      NewMatrix3dValue.Data[0][0] := valueArray.Floats[0];
      NewMatrix3dValue.Data[1][0] := valueArray.Floats[1];
      NewMatrix3dValue.Data[2][0] := valueArray.Floats[2];
      NewMatrix3dValue.Data[0][1] := valueArray.Floats[3];
      NewMatrix3dValue.Data[1][1] := valueArray.Floats[4];
      NewMatrix3dValue.Data[2][1] := valueArray.Floats[5];
      NewMatrix3dValue.Data[0][2] := valueArray.Floats[6];
      NewMatrix3dValue.Data[1][2] := valueArray.Floats[7];
      NewMatrix3dValue.Data[2][2] := valueArray.Floats[8];
      TSFMatrix3d(field).Value := NewMatrix3dValue;
    end else if (field is TSFMatrix3f) and (value is TJSONArray) then begin
      if valueArray.Count < 9 then
        raise Exception.Create('Matrix array must have 9 elements');
      NewMatrix3fValue := TMatrix3.Identity;
      NewMatrix3fValue.Data[0][0] := valueArray.Items[0].AsFloat;
      NewMatrix3fValue.Data[1][0] := valueArray.Items[1].AsFloat;
      NewMatrix3fValue.Data[2][0] := valueArray.Items[2].AsFloat;
      NewMatrix3fValue.Data[0][1] := valueArray.Items[3].AsFloat;
      NewMatrix3fValue.Data[1][1] := valueArray.Items[4].AsFloat;
      NewMatrix3fValue.Data[2][1] := valueArray.Items[5].AsFloat;
      NewMatrix3fValue.Data[0][2] := valueArray.Items[6].AsFloat;
      NewMatrix3fValue.Data[1][2] := valueArray.Items[7].AsFloat;
      NewMatrix3fValue.Data[2][2] := valueArray.Items[8].AsFloat;
      TSFMatrix3f(field).Value := NewMatrix3fValue;
    end else if (field is TSFMatrix4d) and (value is TJSONArray) then begin
      if valueArray.Count < 16 then
        raise Exception.Create('Matrix array must have 16 elements');
  
      {NewMatrix4dValue: TMatrix4;}
      NewMatrix4dValue := TMatrix4Double.Identity;
      NewMatrix4dValue.Data[0][0] := valueArray.Floats[0];
      NewMatrix4dValue.Data[1][0] := valueArray.Floats[1];
      NewMatrix4dValue.Data[2][0] := valueArray.Floats[2];
      NewMatrix4dValue.Data[3][0] := valueArray.Floats[3];
      NewMatrix4dValue.Data[0][1] := valueArray.Floats[4];
      NewMatrix4dValue.Data[1][1] := valueArray.Floats[5];
      NewMatrix4dValue.Data[2][1] := valueArray.Floats[6];
      NewMatrix4dValue.Data[3][1] := valueArray.Floats[7];
      NewMatrix4dValue.Data[0][2] := valueArray.Floats[8];
      NewMatrix4dValue.Data[1][2] := valueArray.Floats[9];
      NewMatrix4dValue.Data[2][2] := valueArray.Floats[10];
      NewMatrix4dValue.Data[3][2] := valueArray.Floats[11];
      NewMatrix4dValue.Data[0][3] := valueArray.Floats[12];
      NewMatrix4dValue.Data[1][3] := valueArray.Floats[13];
      NewMatrix4dValue.Data[2][3] := valueArray.Floats[14];
      NewMatrix4dValue.Data[3][3] := valueArray.Floats[15];
      TSFMatrix4d(field).Value := NewMatrix4dValue;
    end else if (field is TSFMatrix4f) and (value is TJSONArray) then begin
      if valueArray.Count < 16 then
        raise Exception.Create('Matrix array must have 16 elements');
      NewMatrix4fValue := TMatrix4.Identity;
      NewMatrix4fValue.Data[0][0] := valueArray.Items[0].AsFloat;
      NewMatrix4fValue.Data[1][0] := valueArray.Items[1].AsFloat;
      NewMatrix4fValue.Data[2][0] := valueArray.Items[2].AsFloat;
      NewMatrix4fValue.Data[3][0] := valueArray.Items[3].AsFloat;
      NewMatrix4fValue.Data[0][1] := valueArray.Items[4].AsFloat;
      NewMatrix4fValue.Data[1][1] := valueArray.Items[5].AsFloat;
      NewMatrix4fValue.Data[2][1] := valueArray.Items[6].AsFloat;
      NewMatrix4fValue.Data[3][1] := valueArray.Items[7].AsFloat;
      NewMatrix4fValue.Data[0][2] := valueArray.Items[8].AsFloat;
      NewMatrix4fValue.Data[1][2] := valueArray.Items[9].AsFloat;
      NewMatrix4fValue.Data[2][2] := valueArray.Items[10].AsFloat;
      NewMatrix4fValue.Data[3][2] := valueArray.Items[11].AsFloat;
      NewMatrix4fValue.Data[0][3] := valueArray.Items[12].AsFloat;
      NewMatrix4fValue.Data[1][3] := valueArray.Items[13].AsFloat;
      NewMatrix4fValue.Data[2][3] := valueArray.Items[14].AsFloat;
      NewMatrix4fValue.Data[3][3] := valueArray.Items[15].AsFloat;
      TSFMatrix4f(field).Value := NewMatrix4fValue;
    { else if field is TSFNode then
      begin
	    TSFNode(field).Value := value;
      end }
    end else if (field is TSFRotation) and (value is TJSONArray) then begin
      TSFRotation(field).Value := Vector4(
        valueArray.Items[0].AsFloat,
        valueArray.Items[1].AsFloat,
        valueArray.Items[2].AsFloat,
        valueArray.Items[3].AsFloat);
    end else if (field is TSFVec2d) and (value is TJSONArray) then begin
      TSFVec2d(field).Value := Vector2Double(valueArray.Floats[0], valueArray.Floats[1]);
    end else if (field is TSFVec2f) and (value is TJSONArray) then begin
      TSFVec2f(field).Value := Vector2(
        valueArray.Items[0].AsFloat,
        valueArray.Items[1].AsFloat);
    end else if (field is TSFVec3d) and (value is TJSONArray) then begin
      TSFVec3d(field).Value :=Vector3Double( valueArray.Floats[0], valueArray.Floats[1], valueArray.Floats[2]);
    end else if (field is TSFVec3f) and (value is TJSONArray) then begin
      TSFVec3f(field).Value := Vector3(
        valueArray.Items[0].AsFloat,
        valueArray.Items[1].AsFloat,
        valueArray.Items[2].AsFloat);
    end else if (field is TSFVec4d) and (value is TJSONArray) then begin
      TSFVec4d(field).Value := Vector4Double(
        valueArray.Floats[0],
        valueArray.Floats[1],
        valueArray.Floats[2],
        valueArray.Floats[3]);
    end else if (field is TSFVec4f) and (value is TJSONArray) then begin
      TSFVec4f(field).Value := Vector4(
        valueArray.Items[0].AsFloat,
        valueArray.Items[1].AsFloat,
        valueArray.Items[2].AsFloat,
        valueArray.Items[3].AsFloat);
    end;
end;

function TX3DJSONLD.getKey(originalKey: String): String;
begin
  Result := originalKey;
  CastleLog.writeLnLog('key was', Result);
  if (Length(Result) > 0) and ((Result[1] = '-') or (Result[1] = '@')) then
  begin
    Result := Copy(Result, 2, Length(Result)-1);
  end;
  CastleLog.writeLnLog('key is', Result);
end;

function TX3DJSONLD.JSONArrayToImage(const valueArray: TJSONArray): TCastleImage;
var
  Width, Height, Components, PixelCount, I: Integer;
  PixelValue: Cardinal;
  DestIndex: Integer;
  RawData: PByte; // A typed pointer to a Byte
begin
  Result := nil;

  // Metadata Parsing
  if valueArray.Count < 3 then Exit;
  Width := valueArray.Items[0].AsInteger;
  Height := valueArray.Items[1].AsInteger;
  Components := valueArray.Items[2].AsInteger;
  PixelCount := Width * Height;

  // Validation
  if valueArray.Count <> (3 + PixelCount) then Exit;

  // Create the correct class instance
  case Components of
    1: Result := TGrayscaleImage.Create;
    2: Result := TGrayscaleAlphaImage.Create;
    3: Result := TRGBImage.Create;
    4: Result := TRGBAlphaImage.Create;
  else
    Exit;
  end;

  try
    // Set the image size, which allocates the internal FRawPixels buffer
    Result.SetSize(Width, Height);

    // --- THE KEY FIX ---
    // Get the protected pointer and cast it to a PByte *once* before the loop.
    RawData := PByte(TCrackerRGBImage(Result).FRawPixels);

    // Now we can use RawData with simple array notation.
    DestIndex := 0;
    for I := 0 to PixelCount - 1 do
    begin
      PixelValue := Cardinal(valueArray.Items[3 + I].AsInteger);

      case Components of
        4: // RGBA
        begin
          RawData[DestIndex]   := Byte((PixelValue shr 24) and $FF);
          RawData[DestIndex+1] := Byte((PixelValue shr 16) and $FF);
          RawData[DestIndex+2] := Byte((PixelValue shr 8) and $FF);
          RawData[DestIndex+3] := Byte(PixelValue and $FF);
        end;
        3: // RGB
        begin
          RawData[DestIndex]   := Byte((PixelValue shr 24) and $FF);
          RawData[DestIndex+1] := Byte((PixelValue shr 16) and $FF);
          RawData[DestIndex+2] := Byte((PixelValue shr 8) and $FF);
        end;
        2: // Grayscale + Alpha
        begin
          RawData[DestIndex]   := Byte((PixelValue shr 8) and $FF);
          RawData[DestIndex+1] := Byte(PixelValue and $FF);
        end;
        1: // Grayscale
        begin
          RawData[DestIndex]   := Byte(PixelValue and $FF);
        end;
      end;
      Inc(DestIndex, Components);
    end;
  except
    on E: Exception do begin
      FreeAndNil(Result);
      CastleLog.WriteLnLog('Exception during image creation: ' + E.Message);
    end;
  end;
end;

procedure TX3DJSONLD.SetField(root: TX3DRootNode; element: TX3DNode; const key: String; const value: TJSONData); overload;
var
  keyCopy: String;
  field: TX3DField;
begin
  keyCopy := getKey(key);
  field := GetField(element, keyCopy);
  CastleLog.WriteLnLog('key = '+key);
  CastleLog.WriteLnLog('value = '+value.AsString);
  if (element = nil) and not Assigned(element) then begin
    CastleLog.WriteLnLog('ERROR', 'element is nil in SetField');
  end else if (field = nil) and not Assigned(field) then begin
    CastleLog.WriteLnLog('ERROR', 'field is nil in SetField');
  end else if value is TJSONArray then begin
    ConvertJsonArray(root, TJSONArray(value), keyCopy, element, '')
  end else if (field is TSFInt32) and (value is TJSONIntegerNumber) then begin
    SetInt32Field(TSFInt32(field), TJSONIntegerNumber(value));
  end else if (field is TSFInt32) and (value is TJSONInt64Number) then begin
    SetInt64Field(TSFInt32(field), TJSONInt64Number(value));
  end else if (field is TSFDouble) and (value is TJSONNumber) then begin
    SetDoubleField(TSFDouble(field), TJSONNumber(value));
  end else if (field is TSFFloat) and (value is TJSONFloatNumber) then begin
    SetFloatField(TSFFloat(field), TJSONFloatNumber(value));
  end else if (field is TSFString) and (value is TJSONString) then begin
    SetStringField(TSFString(field), TJSONString(value));
  end else if (field is TSFBool) and (value is TJSONBoolean) then begin
    SetBoolField(TSFBool(field), TJSONBoolean(value));
  end;
end;

function TX3DJSONLD.DocumentCreateElement(const key: String): TX3DNode;
var
  clz: TX3DNodeClass;
	{
  clz: TPersistentClass;
  obj: TX3DNode;
  }
  x3dname: string;
begin
  x3dname := key;
  CastleLog.WriteLnLog('REFLECT', 'look up Class for '+x3dname);
  { clz := NodesManager.X3DTypeToClass(x3dname, X3DVersion); }
  try
    clz := nodeFactoryMap[x3dname];
    CastleLog.WriteLnLog('REFLECT', 'found Class for '+clz.ClassX3DType);
    if Assigned(clz) then begin
      Result := clz.Create;
      CastleLog.WriteLnLog('DEBUG', 'Created Element for '+x3dname+' type '+Result.X3DType+' class '+Result.ClassName);
    end else begin
      CastleLog.WriteLnLog('ERROR', 'Could not find Element for strange class variable clz');
      Result := nil;
    end;
  except
    on E: Exception do begin
      Result := nil;
      CastleLog.WriteLnLog('REJECTED', 'did not find Class for '+x3dname);
    end;
  end;
  
end;

function TX3DJSONLD.CreateElement(root: TX3DRootNode; const key: String; 
  const containerField: String; obj: TJSONObject): TX3DNode;
var
  new_object: TJSONObject;
  child: TX3DNode;
  new_key: String;
  name, DEF: String;
  qname: String;
begin
  if (key = 'ProtoDeclare') or (key = 'ExternProtoDeclare') then
  begin
    if Assigned(obj) and Assigned(obj.Find('@name')) then begin
      qname := obj.Strings['@name'];
      if (qname <> '') then begin
        name := StripQuotes(qname);
        if name <> '' then
        begin
          if builtins.IndexOf(name) >= 0 then
            CastleLog.WriteLnLog('Attempt to override builtin name '+name+' rejected')
          else if protos.ContainsKey(name) then
            CastleLog.WriteLnLog('Attempt to override PROTO name '+name+' rejected')
          else
          begin
            CastleLog.WriteLnLog('PROTO name ', name);
            protos.Add(name, obj);
          end;
        end;
      end else begin
            CastleLog.WriteLnLog('no PROTO name ');
      end;
    end;
    
    if Assigned(obj) and Assigned(obj.Find('@DEF')) then
    begin
      DEF := StripQuotes(obj.Strings['@DEF']);
      if DEF <> '' then
      begin
        if builtins.IndexOf(DEF) >= 0 then
          CastleLog.WriteLnLog('Attempt to override builtin name '+DEF+' rejected')
        else if protos.ContainsKey(DEF) then
          CastleLog.WriteLnLog('Attempt to override PROTO DEF '+DEF+' rejected')
        else
        begin
          CastleLog.WriteLnLog('PROTO DEF '+DEF);
          protos.Add(DEF, obj);
        end;
      end;
    end;
  end;
  { CastleLog.WritelnLog('Key is '+key); }
  if protos.TryGetValue(key, new_object) then begin
    new_key := 'ProtoInstance';
    child := Self.DocumentCreateElement(new_key);
    Self.SetField(root, child, 'name', TJSONString.Create(key));
  end else begin
    child := Self.DocumentCreateElement(key);
  end;
  
  if (containerField <> '') and (
    ((containerField = 'geometry') and (key = 'IndexedFaceSet')) or
    ((containerField = 'geometry') and (key = 'Text')) or
    ((containerField = 'geometry') and (key = 'IndexedTriangleSet')) or
    ((containerField = 'geometry') and (key = 'Sphere')) or
    ((containerField = 'geometry') and (key = 'Cylinder')) or
    ((containerField = 'geometry') and (key = 'Cone')) or
    ((containerField = 'geometry') and (key = 'LineSet')) or
    ((containerField = 'geometry') and (key = 'IndexedLineSet')) or
    ((containerField = 'geometry') and (key = 'IndexedTriangleMesh')) or
    ((containerField = 'geometry') and (key = 'Box')) or
    ((containerField = 'geometry') and (key = 'Extrusion')) or
    ((containerField = 'geometry') and (key = 'GeoElevationGrid')) or
    ((containerField = 'shape') and (key = 'Shape')) or
    ((containerField = 'skin') and (key = 'Shape')) or
    ((containerField = 'skin') and (key = 'Transform')) or
    (EndsText('exture', containerField) and (key = 'ImageTexture')) or
    (key = 'HAnimSegment') or
    (key = 'HAnimSite') or
    (key = 'HAnimMotion') or
    ((containerField = 'skinCoord') and (key = 'Coordinate')) or
    ((containerField = 'skin') and (key = 'IndexedFaceSet')) or
    (((containerField = 'skinBindingCoords') or (containerField = 'skinCoord')) and (key = 'Coordinate')) or
    (((containerField = 'normal') or (containerField = 'skinBindingNormals') or (containerField = 'skinNormal')) and (key = 'Normal')) or
    (((containerField = 'skeleton') or (containerField = 'children') or (containerField = 'joints')) and (key = 'HAnimJoint'))
  ) then begin
	  Self.SetField(root, child, 'containerField', TJSONString.Create(containerField));
  end;
  
  Result := child;
end;

procedure TX3DJSONLD.CDATACreateFunction(root: TX3DRootNode; element: TX3DNode; const value: TJSONArray; const typ: TJSONString);
  var
    Effect: TEffectNode;
    EffectPart: TEffectPartNode;
  begin
    Effect := TEffectNode.Create;
    Effect.Language := slGLSL;

    EffectPart := TEffectPartNode.Create;
    if typ.asString = 'FRAGMENT' then begin
    	EffectPart.ShaderType := stFragment;
    end else begin
    	EffectPart.ShaderType := stVertex;
    end;
    EffectPart.SetUrl(['data:text/plain,' + value.asString]);
    Effect.SetParts([EffectPart]);

    scene.SetEffects([Effect]);
  end;

procedure TX3DJSONLD.ConvertProperty(root: TX3DRootNode; const key: String; 
  obj: TJSONObject; element: TX3DNode; const containerField: String);
var
  jsonValue: TJSONData;
  arr: TJSONArray;
  i: Integer;
  comment: TX3DNode;
begin
  if not Assigned(obj) then Exit;
  
  jsonValue := obj.Find(key);
  if (jsonValue = nil) then Exit;
  
  if jsonValue is TJSONObject then begin
    if key = '@sourceCode' then
      Self.CDATACreateFunction(root, element, TJSONArray(jsonValue), TJSONString(obj.Find('@type').asString))
    else if (Length(key) > 0) and (key[1] = '@') then
      ConvertJsonValue(root, jsonValue, key, element, containerField)
    else if (Length(key) > 0) and (key[1] = '-') then
      ConvertJsonValue(root, jsonValue, key, element, Copy(key, 2, Length(key)-1))
    else if key = '#comment' then
    begin
      if jsonValue is TJSONArray then
      begin
        arr := TJSONArray(jsonValue);
        for i := 0 to arr.Count - 1 do
        begin
          comment := Self.DocumentCreateComment(arr.Items[i].AsString);
    	  Self.AddChild(element, comment);
        end;
      end
      else
      begin
        comment := Self.DocumentCreateComment(jsonValue.AsString);
    	Self.AddChild(element, comment);
      end;
    end
    else if key = '#sourceCode' then
      Self.CDATACreateFunction(root, element, TJSONArray(jsonValue), TJSONString(obj.Find('@type').asString))
    else if (key = 'connect') or (key = 'fieldValue') or (key = 'field') or 
            (key = 'meta') or (key = 'component') or (key = 'unit') then
    begin
      arr := TJSONArray(jsonValue);
      ConvertJsonArray(root, arr, key, element, containerField);
    end else  begin
      ConvertJsonValue(root, jsonValue, key, element, containerField);
    end;
  end else begin
	  { TODO  else if key = '#comment' then }
  end;
end;

function TX3DJSONLD.DocumentCreateComment(const arr: String) : TX3DNode;
begin
	{ Result := TX3DCommentNode.Create; }
	{ Result.Comment := CommentString(arr); }
  Result := nil;
end;

function TX3DJSONLD.CommentString(const str: String): String;
var
  x, y: String;
begin
  y := str;
  Result := y;
  
  repeat
    x := Result;
    Result := StringReplace(x, '\"', '"', [rfReplaceAll]);
  until x = Result;
  
  repeat
    x := Result;
    Result := StringReplace(x, '""', '" "', [rfReplaceAll]);
  until x = Result;
end;

function TX3DJSONLD.NavigationInfoTypeToAttributeValue(const str: String): TJSONString;
begin
  CastleLog.WriteLnLog('X3DJSONLD3 jsonstring replacing ', str);
  Result := TJSONString.Create(StringReplace(str, '\', '', [rfReplaceAll]));
  if TJSONString.Create(str) <> Result then
    CastleLog.WriteLnLog('with                           '+ Result.asString)
  else
    CastleLog.WriteLnLog('ok');
end;

procedure TX3DJSONLD.ConvertJsonObject(root: TX3DRootNode; obj: TJSONObject; 
  const parentkey: String; element: TX3DNode; const containerField: String);
var
  kii: Boolean;
  child: TX3DNode;
  i: Integer;
  key: String;
  jsonValue: TJSONData;
  comment: TX3DNode;
  tempContainerField: String;
  tempInt: LongInt;
begin
  tempContainerField := '';
  key := '';
  if not Assigned(obj) then Exit;
  
  kii := TryStrToInt(parentkey, tempInt);
  
  if kii or (Length(parentkey) > 0) and (parentkey[1] = '-') then
    child := element
  else
  begin
    tempContainerField := containerField;
    
    if ((tempContainerField = '') or (tempContainerField = 'children')) and 
       (parentkey = 'HAnimJoint') and (element.ClassX3DType = 'HAnimHumanoid') then
      tempContainerField := 'joints';
      
    if ((tempContainerField = '') or (tempContainerField = 'coord')) and 
       (parentkey = 'Coordinate') and (element.ClassX3DType = 'HAnimHumanoid') then
      tempContainerField := 'skinCoord';
      
    child := Self.CreateElement(root, parentkey, tempContainerField, obj);
  end;
  
  for i := 0 to obj.Count - 1 do
  begin
    key := obj.Names[i];
    jsonValue := obj.Items[i];
    
    if jsonValue is TJSONObject then begin
      if (key = '@type') and (parentkey = 'NavigationInfo') then
        Self.SetField(root, child, Copy(key, 2, Length(key)-1), 
          NavigationInfoTypeToAttributeValue(jsonValue.AsString))
      else if (Length(key) > 0) and (key[1] = '@') then
        ConvertProperty(root, key, TJSONObject(jsonValue), child, containerField)
      else if (Length(key) > 0) and (key[1] = '-') then
        ConvertJsonObject(root, TJSONObject(jsonValue), key, child, Copy(key, 2, Length(key)-1))
      else
        ConvertJsonObject(root, TJSONObject(jsonValue), key, child, containerField);
    end else if jsonValue is TJSONArray then
      ConvertJsonArray(root, TJSONArray(jsonValue), key, child, containerField)
    else if jsonValue is TJSONNumber then
      Self.SetField(root, child, Copy(key, 2, Length(key)-1), jsonValue)
    else if jsonValue is TJSONString then begin
      if key = '#comment' then
      begin
        comment := Self.DocumentCreateComment(jsonValue.AsString);
    	Self.AddChild(child, comment);
      end
      else if (key = '@type') and (parentkey = 'NavigationInfo') then
        Self.SetField(root, child, Copy(key, 2, Length(key)-1), 
          NavigationInfoTypeToAttributeValue(jsonValue.AsString))
      else
        Self.SetField(root, child, Copy(key, 2, Length(key)-1), jsonValue);
    end else if (jsonValue is TJSONBoolean) then begin
      Self.SetField(root, child, Copy(key, 2, Length(key)-1), jsonValue);
    end else if (jsonValue is TJSONNull) then begin
      Self.SetField(root, child, Copy(key, 2, Length(key)-1), jsonValue);
    end;
  end;
  
  if not kii and not ((Length(parentkey) > 0) and (parentkey[1] = '-')) then
    Self.AddChild(element, child);
end;

procedure TX3DJSONLD.AddChild(parentNode: TX3DNode; childNode: TX3DNode); 
var
  AShape: TShapeNode;
begin
  if (parentNode = nil) then begin
    CastleLog.WriteLnLog('Warning: parent is nil.');
    Exit;
  end;
  if (childNode = nil) then begin
    CastleLog.WriteLnLog('Warning: child is nil.');
    Exit;
  end;
  if (parentNode = childNode) then begin
    CastleLog.WriteLnLog('Warning: parent = child.');
    Exit;
  end;
  if not Assigned(parentNode) or not Assigned(childNode) then begin
    CastleLog.WriteLnLog('Warning: Tried a childs to a parent. One is unassigned.');
    Exit;
  end;
  CastleLog.WriteLnLog('DEBUG: Trying  to add child %s to parent %s.', [childNode.ClassName, parentNode.ClassName]);
  if (parentNode is TAbstractGroupingNode) and (childNode is TAbstractChildNode) then begin
    TAbstractGroupingNode(parentNode).AddChildren(TAbstractChildNode(childNode));
    CastleLog.WriteLnLog('DEBUG', 'Added 1');
  end else if (parentNode is TX3DRootNode) and (childNode is TAbstractChildNode) then begin
    TX3DRootNode(parentNode).AddChildren(TAbstractChildNode(childNode));
    CastleLog.WriteLnLog('DEBUG', 'Added 2');
  end else if (parentNode is TX3DRootNode) and (childNode is TAbstractGeometryNode) then begin
    AShape := TShapeNode.Create;
    TAbstractGeometryNode(childNode).CreateWithShape(AShape);
    TX3DRootNode(parentNode).AddChildren(AShape);
    CastleLog.WriteLnLog('DEBUG', 'Added 3');
  end else begin
    CastleLog.WriteLnLog('TODO: Tried to add a child node of type %s to a parent node of type %s', [childNode.X3DType, parentNode.X3DType]);
  end;
end;

procedure TX3DJSONLD.ConvertJsonArray(root: TX3DRootNode; arr: TJSONArray; 
  const parentkey: String; element: TX3DNode; const containerField: String);
var
  arrayOfStrings: Boolean;
  localArray: TJSONArray;
  arraysize, i: Integer;
  jsonValue: TJSONData;
  kii: Boolean;
begin
  if not Assigned(arr) then Exit;
  
  arrayOfStrings := False;
  localArray := TJSONArray.Create;
  try
    arraysize := arr.Count;
    
    if parentkey = 'meta' then begin
      if x3dTidy then begin
        arraysize := arr.Count - 2;
      end else begin
        arraysize := arr.Count - 3;
      end;
    end;
    
    for i := 0 to arraysize - 1 do
    begin
      jsonValue := arr.Items[i];
      
      if jsonValue is TJSONNumber then begin
        localArray.Add(jsonValue.AsString)
      end else if jsonValue is TJSONString then begin
        localArray.Add('"'+jsonValue.AsString+'"');
        arrayOfStrings := True;
      end else if (jsonValue is TJSONBoolean) then begin
        localArray.Add(UpperCase(jsonValue.AsString));
      end else if jsonValue is TJSONObject then begin
        try
          StrToInt(IntToStr(i));
          kii := True;
        except
          kii := False;
        end;
        
        if not ((Length(parentkey) > 0) and (parentkey[1] = '-')) and kii then begin
          ConvertJsonValue(root, jsonValue, parentkey, element, containerField)
        end else begin
          ConvertJsonValue(root, jsonValue, IntToStr(i), element, Copy(parentkey, 2, Length(parentkey)-1));
	end;
      end else if jsonValue is TJSONArray then begin
        ConvertJsonValue(root, jsonValue, IntToStr(i), element, containerField);
      end else if (jsonValue = nil) or (jsonValue is TJSONNull) then begin
        localArray.Add('');
      end;
    end;
    
    if parentkey = '@sourceCode' then begin
      Self.CDATACreateFunction(root, element, arr, TJSONString.Create(''))
    end else if (Length(parentkey) > 0) and (parentkey[1] = '@') then begin
      CastleLog.writeLnLog('INFO', 'parent key is = '+parentKey);
      Self.SetArrayField(GetField(element, Copy(parentkey, 2, Length(parentkey)-1)), localArray)
    end else if (parentkey = '#sourceCode') then begin
      Self.CDATACreateFunction(root, element, arr, TJSONString.Create(''));
    end;
  finally
    localArray.Free;
  end;
end;

function TX3DJSONLD.ConvertJsonValue(root: TX3DRootNode; value: TJSONData; 
  const parentkey: String; element: TX3DNode; const containerField: String): TX3DNode;
var
  comment: TX3DNode;
begin
  if value is TJSONArray then
    ConvertJsonArray(root, TJSONArray(value), parentkey, element, containerField)
  else
    ConvertJsonObject(root, TJSONObject(value), parentkey, element, containerField);
  
  Result := element;
end;

function TX3DJSONLD.LoadJsonIntoDocument(jsobj: TJSONObject; const version: String; x3dTidyFlag: Boolean): TX3DRootNode;
var
  unenversion: String;
  element: TX3DNode;
  x3dObj: TJSONObject;
begin
  x3dTidy := x3dTidyFlag;
  Result := TX3DRootNode.Create;
  element := Self.DocumentCreateElement('X3D');
  x3dObj := TJSONObject(jsobj.Find('X3D'));
  if Assigned(x3dObj) then
    ConvertJsonObject(Result, x3dObj, '-', element, '');
  Self.AddChild(Result, element);
end;

function TX3DJSONLD.ReadJsonFile(const filename: String): TJSONObject;
var
  fileStream: TFileStream;
  parser: TJSONParser;
begin
  fileStream := TFileStream.Create(filename, fmOpenRead);
  try
    parser := TJSONParser.Create(fileStream);
    try
      Result := TJSONObject(parser.Parse);
    finally
      parser.Free;
    end;
  finally
    fileStream.Free;
  end;
end;

function TX3DJSONLD.GetX3DVersion(jsobj: TJSONObject): String;
var
  x3dObj: TJSONObject;
  versionData: TJSONData;
begin
  Result := '4.0';
  if Assigned(jsobj) then
  begin
    x3dObj := TJSONObject(jsobj.Find('X3D'));
    if Assigned(x3dObj) then
    begin
      versionData := x3dObj.Find('@version');
      if Assigned(versionData) then
        Result := StringReplace(versionData.AsString, '"', '', [rfReplaceAll]);
    end;
  end;
end;

function LoadX3DJsonInternal(const Stream: TStream; const BaseUrl: String): TX3DRootNode; overload;
var
    jsobj: TJSONData;
begin
  try
   jsobj := GetJSON(Stream);
    if jsobj is TJSONObject then
    begin
      Result := TX3DJSONLD.localJSON.LoadJsonIntoDocument(TJSONObject(jsobj), '4.0', False);
    end;
  finally
    jsobj.Free;
  end;
end;

procedure TX3DJSONLD.RegisterJSON;
var
  ModelFormat: TModelFormat;
begin
  ModelFormat := TModelFormat.Create;
  ModelFormat.OnLoad := {$ifdef FPC}@{$endif} LoadX3DJsonInternal;
  ModelFormat.MimeTypes.Add('model/x3d+json');
  ModelFormat.FileFilterName := 'X3D JSON (*.x3dj)';
  ModelFormat.Extensions.Add('.x3dj');
  RegisterModelFormat(ModelFormat);
  UriMimeExtensions['.x3dj'] := 'model/x3d+json';
end;

procedure TX3DJSONLD.Factory;
begin
  nodeFactoryMap.Add('X3DAppearanceChildNode', nil);
  nodeFactoryMap.Add('X3DAppearanceNode', nil);
  nodeFactoryMap.Add('X3DArrayField', nil);
  nodeFactoryMap.Add('X3DBackgroundNode', nil);
  nodeFactoryMap.Add('X3DBindableNode', nil);
  nodeFactoryMap.Add('X3DChaserNode', nil);
  nodeFactoryMap.Add('X3DChildNode', nil);
  nodeFactoryMap.Add('X3DColorNode', nil);
  nodeFactoryMap.Add('X3DComposableVolumeRenderStyleNode', nil);
  nodeFactoryMap.Add('X3DComposedGeometryNode', nil);
  nodeFactoryMap.Add('X3DCoordinateNode', nil);
  nodeFactoryMap.Add('X3DDamperNode', nil);
  nodeFactoryMap.Add('X3DDragSensorNode', nil);
  nodeFactoryMap.Add('X3DEnvironmentalSensorNode', nil);
  nodeFactoryMap.Add('X3DEnvironmentTextureNode', nil);
  nodeFactoryMap.Add('X3DField', nil);
  nodeFactoryMap.Add('X3DFollowerNode', nil);
  nodeFactoryMap.Add('X3DFontStyleNode', nil);
  nodeFactoryMap.Add('X3DGeometricPropertyNode', nil);
  nodeFactoryMap.Add('X3DGeometryNode', nil);
  nodeFactoryMap.Add('X3DGroupingNode', nil);
  nodeFactoryMap.Add('X3DInfoNode', nil);
  nodeFactoryMap.Add('X3DInterpolatorNode', nil);
  nodeFactoryMap.Add('X3DKeyDeviceSensorNode', nil);
  nodeFactoryMap.Add('X3DLayerNode', nil);
  nodeFactoryMap.Add('X3DLayoutNode', nil);
  nodeFactoryMap.Add('X3DLightNode', nil);
  nodeFactoryMap.Add('X3DMaterialNode', nil);
  nodeFactoryMap.Add('X3DNBodyCollidableNode', nil);
  nodeFactoryMap.Add('X3DNBodyCollisionSpaceNode', nil);
  nodeFactoryMap.Add('X3DNetworkSensorNode', nil);
  nodeFactoryMap.Add('X3DNode', nil);
  nodeFactoryMap.Add('X3DNormalNode', nil);
  nodeFactoryMap.Add('X3DNurbsControlCurveNode', nil);
  nodeFactoryMap.Add('X3DNurbsSurfaceGeometryNode', nil);
  nodeFactoryMap.Add('X3DOneSidedMaterialNode', nil);
  nodeFactoryMap.Add('X3DParametricGeometryNode', nil);
  nodeFactoryMap.Add('X3DParticleEmitterNode', nil);
  nodeFactoryMap.Add('X3DParticlePhysicsModelNode', nil);
  nodeFactoryMap.Add('X3DPickSensorNode', nil);
  nodeFactoryMap.Add('X3DPointingDeviceSensorNode', nil);
  nodeFactoryMap.Add('X3DProductStructureChildNode', nil);
  nodeFactoryMap.Add('X3DPrototypeInstance', nil);
  nodeFactoryMap.Add('X3DRigidJointNode', nil);
  nodeFactoryMap.Add('X3DScriptNode', nil);
  nodeFactoryMap.Add('X3DSensorNode', nil);
  nodeFactoryMap.Add('X3DSequencerNode', nil);
  nodeFactoryMap.Add('X3DShaderNode', nil);
  nodeFactoryMap.Add('X3DShapeNode', nil);
  nodeFactoryMap.Add('X3DSingleTextureCoordinateNode', nil);
  nodeFactoryMap.Add('X3DSingleTextureNode', nil);
  nodeFactoryMap.Add('X3DSingleTextureTransformNode', nil);
  nodeFactoryMap.Add('X3DSoundChannelNode', nil);
  nodeFactoryMap.Add('X3DSoundDestinationNode', nil);
  nodeFactoryMap.Add('X3DSoundNode', nil);
  nodeFactoryMap.Add('X3DSoundProcessingNode', nil);
  nodeFactoryMap.Add('X3DSoundSourceNode', nil);
  nodeFactoryMap.Add('X3DStatement', nil);
  nodeFactoryMap.Add('X3DTexture2DNode', nil);
  nodeFactoryMap.Add('X3DTexture3DNode', nil);
  nodeFactoryMap.Add('X3DTextureCoordinateNode', nil);
  nodeFactoryMap.Add('X3DTextureNode', nil);
  nodeFactoryMap.Add('X3DTextureProjectorNode', nil);
  nodeFactoryMap.Add('X3DTextureTransformNode', nil);
  nodeFactoryMap.Add('X3DTimeDependentNode', nil);
  nodeFactoryMap.Add('X3DTouchSensorNode', nil);
  nodeFactoryMap.Add('X3DTriggerNode', nil);
  nodeFactoryMap.Add('X3DVertexAttributeNode', nil);
  nodeFactoryMap.Add('X3DViewpointNode', nil);
  nodeFactoryMap.Add('X3DViewportNode', nil);
  nodeFactoryMap.Add('X3DVolumeDataNode', nil);
  nodeFactoryMap.Add('X3DVolumeRenderStyleNode', nil);
  nodeFactoryMap.Add('X3DMaterialExtensionNode', nil);
  nodeFactoryMap.Add('X3DBoundedObject', nil);
  nodeFactoryMap.Add('X3DFogObject', nil);
  nodeFactoryMap.Add('X3DMetadataObject', nil);
  nodeFactoryMap.Add('X3DPickableObject', nil);
  nodeFactoryMap.Add('X3DProgrammableShaderObject', nil);
  nodeFactoryMap.Add('X3DUrlObject', nil);
  
  // X3D concrete node types
  { nodeFactoryMap.Add('AcousticProperties', TAcousticPropertiesNode); }
  { nodeFactoryMap.Add('Analyser', TAnalyserNode); }
  nodeFactoryMap.Add('Anchor', TAnchorNode);
  nodeFactoryMap.Add('Appearance', TAppearanceNode);
  nodeFactoryMap.Add('Arc2D', TArc2DNode);
  nodeFactoryMap.Add('ArcClose2D', TArcClose2DNode);
  nodeFactoryMap.Add('AudioClip', TAudioClipNode);
  { nodeFactoryMap.Add('AudioDestination', TAudioDestinationNode); }
  nodeFactoryMap.Add('Background', TBackgroundNode);
  nodeFactoryMap.Add('BallJoint', TBallJointNode);
  nodeFactoryMap.Add('Billboard', TBillboardNode);
  { nodeFactoryMap.Add('BiquadFilter', TBiquadFilterNode); }
  { nodeFactoryMap.Add('BlendedVolumeStyle', TBlendedVolumeStyleNode); }
  nodeFactoryMap.Add('BooleanFilter', TBooleanFilterNode);
  nodeFactoryMap.Add('BooleanSequencer', TBooleanSequencerNode);
  nodeFactoryMap.Add('BooleanToggle', TBooleanToggleNode);
  nodeFactoryMap.Add('BooleanTrigger', TBooleanTriggerNode);
  { nodeFactoryMap.Add('BoundaryEnhancementVolumeStyle', TBoundaryEnhancementVolumeStyleNode); }
  nodeFactoryMap.Add('BoundedPhysicsModel', TBoundedPhysicsModelNode);
  nodeFactoryMap.Add('Box', TBoxNode);
  { nodeFactoryMap.Add('BufferAudioSource', TBufferAudioSourceNode); }
  nodeFactoryMap.Add('CADAssembly', TCADAssemblyNode);
  nodeFactoryMap.Add('CADFace', TCADFaceNode);
  nodeFactoryMap.Add('CADLayer', TCADLayerNode);
  nodeFactoryMap.Add('CADPart', TCADPartNode);
  { nodeFactoryMap.Add('CartoonVolumeStyle', TCartoonVolumeStyleNode); }
  { nodeFactoryMap.Add('ChannelMerger', TChannelMergerNode); }
  { nodeFactoryMap.Add('ChannelSelector', TChannelSelectorNode); }
  { nodeFactoryMap.Add('ChannelSplitter', TChannelSplitterNode); }
  nodeFactoryMap.Add('Circle2D', TCircle2DNode);
  nodeFactoryMap.Add('ClipPlane', TClipPlaneNode);
  nodeFactoryMap.Add('CollidableOffset', TCollidableOffsetNode);
  nodeFactoryMap.Add('CollidableShape', TCollidableShapeNode);
  nodeFactoryMap.Add('Collision', TCollisionNode);
  nodeFactoryMap.Add('CollisionCollection', TCollisionCollectionNode);
  nodeFactoryMap.Add('CollisionSensor', TCollisionSensorNode);
  nodeFactoryMap.Add('CollisionSpace', TCollisionSpaceNode);
  nodeFactoryMap.Add('Color', TColorNode);
  { nodeFactoryMap.Add('ColorChaser', TColorChaserNode); }
  nodeFactoryMap.Add('ColorDamper', TColorDamperNode);
  nodeFactoryMap.Add('ColorInterpolator', TColorInterpolatorNode);
  nodeFactoryMap.Add('ColorRGBA', TColorRGBANode);
  nodeFactoryMap.Add('ComposedCubeMapTexture', TComposedCubeMapTextureNode);
  nodeFactoryMap.Add('ComposedShader', TComposedShaderNode);
  nodeFactoryMap.Add('ComposedTexture3D', TComposedTexture3DNode);
  { nodeFactoryMap.Add('ComposedVolumeStyle', TComposedVolumeStyleNode); }
  nodeFactoryMap.Add('Cone', TConeNode);
  nodeFactoryMap.Add('ConeEmitter', TConeEmitterNode);
  nodeFactoryMap.Add('Contact', TContactNode);
  nodeFactoryMap.Add('Contour2D', TContour2DNode);
  nodeFactoryMap.Add('ContourPolyline2D', TContourPolyline2DNode);
  { nodeFactoryMap.Add('Convolver', TConvolverNode); }
  nodeFactoryMap.Add('Coordinate', TCoordinateNode);
  { nodeFactoryMap.Add('CoordinateChaser', TCoordinateChaserNode); }
  nodeFactoryMap.Add('CoordinateDamper', TCoordinateDamperNode);
  nodeFactoryMap.Add('CoordinateDouble', TCoordinateDoubleNode);
  nodeFactoryMap.Add('CoordinateInterpolator', TCoordinateInterpolatorNode);
  nodeFactoryMap.Add('CoordinateInterpolator2D', TCoordinateInterpolator2DNode);
  nodeFactoryMap.Add('Cylinder', TCylinderNode);
  nodeFactoryMap.Add('CylinderSensor', TCylinderSensorNode);
  { nodeFactoryMap.Add('Delay', TDelayNode); }
  nodeFactoryMap.Add('DirectionalLight', TDirectionalLightNode);
  nodeFactoryMap.Add('DISEntityManager', TDISEntityManagerNode);
  nodeFactoryMap.Add('DISEntityTypeMapping', TDISEntityTypeMappingNode);
  nodeFactoryMap.Add('Disk2D', TDisk2DNode);
  nodeFactoryMap.Add('DoubleAxisHingeJoint', TDoubleAxisHingeJointNode);
  { nodeFactoryMap.Add('DynamicsCompressor', TDynamicsCompressorNode); }
  nodeFactoryMap.Add('EaseInEaseOut', TEaseInEaseOutNode);
  { nodeFactoryMap.Add('EdgeEnhancementVolumeStyle', TEdgeEnhancementVolumeStyleNode); }
  nodeFactoryMap.Add('ElevationGrid', TElevationGridNode);
  nodeFactoryMap.Add('EspduTransform', TEspduTransformNode);
  nodeFactoryMap.Add('ExplosionEmitter', TExplosionEmitterNode);
  nodeFactoryMap.Add('Extrusion', TExtrusionNode);
  nodeFactoryMap.Add('FillProperties', TFillPropertiesNode);
  nodeFactoryMap.Add('FloatVertexAttribute', TFloatVertexAttributeNode);
  nodeFactoryMap.Add('Fog', TFogNode);
  nodeFactoryMap.Add('FogCoordinate', TFogCoordinateNode);
  nodeFactoryMap.Add('FontStyle', TFontStyleNode);
  nodeFactoryMap.Add('ForcePhysicsModel', TForcePhysicsModelNode);
  { nodeFactoryMap.Add('Gain', TGainNode); }
  nodeFactoryMap.Add('GeneratedCubeMapTexture', TGeneratedCubeMapTextureNode);
  nodeFactoryMap.Add('GeoCoordinate', TGeoCoordinateNode);
  nodeFactoryMap.Add('GeoElevationGrid', TGeoElevationGridNode);
  nodeFactoryMap.Add('GeoLocation', TGeoLocationNode);
  nodeFactoryMap.Add('GeoLOD', TGeoLODNode);
  nodeFactoryMap.Add('GeoMetadata', TGeoMetadataNode);
  nodeFactoryMap.Add('GeoOrigin', TGeoOriginNode);
  nodeFactoryMap.Add('GeoPositionInterpolator', TGeoPositionInterpolatorNode);
  nodeFactoryMap.Add('GeoProximitySensor', TGeoProximitySensorNode);
  nodeFactoryMap.Add('GeoTouchSensor', TGeoTouchSensorNode);
  nodeFactoryMap.Add('GeoTransform', TGeoTransformNode);
  nodeFactoryMap.Add('GeoViewpoint', TGeoViewpointNode);
  nodeFactoryMap.Add('Group', TGroupNode);
  nodeFactoryMap.Add('HAnimDisplacer', THAnimDisplacerNode);
  nodeFactoryMap.Add('HAnimHumanoid', THAnimHumanoidNode);
  nodeFactoryMap.Add('HAnimJoint', THAnimJointNode);
  nodeFactoryMap.Add('HAnimMotion', THAnimMotionNode);
  nodeFactoryMap.Add('HAnimSegment', THAnimSegmentNode);
  nodeFactoryMap.Add('HAnimSite', THAnimSiteNode);
  nodeFactoryMap.Add('ImageCubeMapTexture', TImageCubeMapTextureNode);
  nodeFactoryMap.Add('ImageTexture', TImageTextureNode);
  nodeFactoryMap.Add('ImageTexture3D', TImageTexture3DNode);
  nodeFactoryMap.Add('IndexedFaceSet', TIndexedFaceSetNode);
  nodeFactoryMap.Add('IndexedLineSet', TIndexedLineSetNode);
  nodeFactoryMap.Add('IndexedQuadSet', TIndexedQuadSetNode);
  nodeFactoryMap.Add('IndexedTriangleFanSet', TIndexedTriangleFanSetNode);
  nodeFactoryMap.Add('IndexedTriangleSet', TIndexedTriangleSetNode);
  nodeFactoryMap.Add('IndexedTriangleStripSet', TIndexedTriangleStripSetNode);
  nodeFactoryMap.Add('Inline', TInlineNode);
  nodeFactoryMap.Add('IntegerSequencer', TIntegerSequencerNode);
  nodeFactoryMap.Add('IntegerTrigger', TIntegerTriggerNode);
  { nodeFactoryMap.Add('IsoSurfaceVolumeData', TIsoSurfaceVolumeDataNode); }
  nodeFactoryMap.Add('KeySensor', TKeySensorNode);
  nodeFactoryMap.Add('Layer', TLayerNode);
  nodeFactoryMap.Add('LayerSet', TLayerSetNode);
  nodeFactoryMap.Add('Layout', TLayoutNode);
  nodeFactoryMap.Add('LayoutGroup', TLayoutGroupNode);
  nodeFactoryMap.Add('LayoutLayer', TLayoutLayerNode);
  nodeFactoryMap.Add('LinePickSensor', TLinePickSensorNode);
  nodeFactoryMap.Add('LineProperties', TLinePropertiesNode);
  nodeFactoryMap.Add('LineSet', TLineSetNode);
  { nodeFactoryMap.Add('ListenerPointSource', TListenerPointSourceNode); }
  nodeFactoryMap.Add('LoadSensor', TLoadSensorNode);
  nodeFactoryMap.Add('LocalFog', TLocalFogNode);
  nodeFactoryMap.Add('LOD', TLODNode);
  nodeFactoryMap.Add('Material', TMaterialNode);
  nodeFactoryMap.Add('Matrix3VertexAttribute', TMatrix3VertexAttributeNode);
  nodeFactoryMap.Add('Matrix4VertexAttribute', TMatrix4VertexAttributeNode);
  nodeFactoryMap.Add('MetadataBoolean', TMetadataBooleanNode);
  nodeFactoryMap.Add('MetadataDouble', TMetadataDoubleNode);
  nodeFactoryMap.Add('MetadataFloat', TMetadataFloatNode);
  nodeFactoryMap.Add('MetadataInteger', TMetadataIntegerNode);
  nodeFactoryMap.Add('MetadataSet', TMetadataSetNode);
  nodeFactoryMap.Add('MetadataString', TMetadataStringNode);
  { nodeFactoryMap.Add('MicrophoneSource', TMicrophoneSourceNode); }
  nodeFactoryMap.Add('MotorJoint', TMotorJointNode);
  nodeFactoryMap.Add('MovieTexture', TMovieTextureNode);
  nodeFactoryMap.Add('MultiTexture', TMultiTextureNode);
  nodeFactoryMap.Add('MultiTextureCoordinate', TMultiTextureCoordinateNode);
  nodeFactoryMap.Add('MultiTextureTransform', TMultiTextureTransformNode);
  nodeFactoryMap.Add('NavigationInfo', TNavigationInfoNode);
  nodeFactoryMap.Add('Normal', TNormalNode);
  nodeFactoryMap.Add('NormalInterpolator', TNormalInterpolatorNode);
  nodeFactoryMap.Add('NurbsCurve', TNurbsCurveNode);
  nodeFactoryMap.Add('NurbsCurve2D', TNurbsCurve2DNode);
  nodeFactoryMap.Add('NurbsOrientationInterpolator', TNurbsOrientationInterpolatorNode);
  nodeFactoryMap.Add('NurbsPatchSurface', TNurbsPatchSurfaceNode);
  nodeFactoryMap.Add('NurbsPositionInterpolator', TNurbsPositionInterpolatorNode);
  nodeFactoryMap.Add('NurbsSet', TNurbsSetNode);
  nodeFactoryMap.Add('NurbsSurfaceInterpolator', TNurbsSurfaceInterpolatorNode);
  nodeFactoryMap.Add('NurbsSweptSurface', TNurbsSweptSurfaceNode);
  nodeFactoryMap.Add('NurbsSwungSurface', TNurbsSwungSurfaceNode);
  nodeFactoryMap.Add('NurbsTextureCoordinate', TNurbsTextureCoordinateNode);
  nodeFactoryMap.Add('NurbsTrimmedSurface', TNurbsTrimmedSurfaceNode);
  { nodeFactoryMap.Add('OpacityMapVolumeStyle', TOpacityMapVolumeStyleNode); }
  nodeFactoryMap.Add('OrientationChaser', TOrientationChaserNode);
  nodeFactoryMap.Add('OrientationDamper', TOrientationDamperNode);
  nodeFactoryMap.Add('OrientationInterpolator', TOrientationInterpolatorNode);
  nodeFactoryMap.Add('OrthoViewpoint', TOrthoViewpointNode);
  { nodeFactoryMap.Add('OscillatorSource', TOscillatorSourceNode); }
  nodeFactoryMap.Add('PackagedShader', TPackagedShaderNode);
  nodeFactoryMap.Add('ParticleSystem', TParticleSystemNode);
  { nodeFactoryMap.Add('PeriodicWave', TPeriodicWaveNode); }
  nodeFactoryMap.Add('PhysicalMaterial', TPhysicalMaterialNode);
  nodeFactoryMap.Add('PickableGroup', TPickableGroupNode);
  nodeFactoryMap.Add('PixelTexture', TPixelTextureNode);
  nodeFactoryMap.Add('PixelTexture3D', TPixelTexture3DNode);
  nodeFactoryMap.Add('PlaneSensor', TPlaneSensorNode);
  nodeFactoryMap.Add('PointEmitter', TPointEmitterNode);
  nodeFactoryMap.Add('PointLight', TPointLightNode);
  nodeFactoryMap.Add('PointPickSensor', TPointPickSensorNode);
  { nodeFactoryMap.Add('PointProperties', TPointPropertiesNode); }
  nodeFactoryMap.Add('PointSet', TPointSetNode);
  nodeFactoryMap.Add('Polyline2D', TPolyline2DNode);
  nodeFactoryMap.Add('PolylineEmitter', TPolylineEmitterNode);
  nodeFactoryMap.Add('Polypoint2D', TPolypoint2DNode);
  nodeFactoryMap.Add('PositionChaser', TPositionChaserNode);
  nodeFactoryMap.Add('PositionChaser2D', TPositionChaser2DNode);
  nodeFactoryMap.Add('PositionDamper', TPositionDamperNode);
  nodeFactoryMap.Add('PositionDamper2D', TPositionDamper2DNode);
  nodeFactoryMap.Add('PositionInterpolator', TPositionInterpolatorNode);
  nodeFactoryMap.Add('PositionInterpolator2D', TPositionInterpolator2DNode);
  nodeFactoryMap.Add('PrimitivePickSensor', TPrimitivePickSensorNode);
  nodeFactoryMap.Add('ProgramShader', TProgramShaderNode);
  { nodeFactoryMap.Add('ProjectionVolumeStyle', TProjectionVolumeStyleNode); }
  nodeFactoryMap.Add('ProtoInstance', TGroupNode); { TODO fix }
  nodeFactoryMap.Add('ProximitySensor', TProximitySensorNode);
  nodeFactoryMap.Add('QuadSet', TQuadSetNode);
  nodeFactoryMap.Add('ReceiverPdu', TReceiverPduNode);
  nodeFactoryMap.Add('Rectangle2D', TRectangle2DNode);
  nodeFactoryMap.Add('RigidBody', TRigidBodyNode);
  nodeFactoryMap.Add('RigidBodyCollection', TRigidBodyCollectionNode);
  nodeFactoryMap.Add('ScalarChaser', TScalarChaserNode);
  { nodeFactoryMap.Add('ScalarDamper', TScalarDamperNode); }
  nodeFactoryMap.Add('ScalarInterpolator', TScalarInterpolatorNode);
  nodeFactoryMap.Add('ScreenFontStyle', TScreenFontStyleNode);
  nodeFactoryMap.Add('ScreenGroup', TScreenGroupNode);
  nodeFactoryMap.Add('Script', TScriptNode);
  { nodeFactoryMap.Add('SegmentedVolumeData', TSegmentedVolumeDataNode); }
  { nodeFactoryMap.Add('ShadedVolumeStyle', TShadedVolumeStyleNode); }
  nodeFactoryMap.Add('ShaderPart', TShaderPartNode);
  nodeFactoryMap.Add('ShaderProgram', TShaderProgramNode);
  nodeFactoryMap.Add('Shape', TShapeNode);
  nodeFactoryMap.Add('SignalPdu', TSignalPduNode);
  { nodeFactoryMap.Add('SilhouetteEnhancementVolumeStyle', TSilhouetteEnhancementVolumeStyleNode); }
  nodeFactoryMap.Add('SingleAxisHingeJoint', TSingleAxisHingeJointNode);
  nodeFactoryMap.Add('SliderJoint', TSliderJointNode);
  nodeFactoryMap.Add('Sound', TSoundNode);
  { nodeFactoryMap.Add('SpatialSound', TSpatialSoundNode); }
  nodeFactoryMap.Add('Sphere', TSphereNode);
  nodeFactoryMap.Add('SphereSensor', TSphereSensorNode);
  nodeFactoryMap.Add('SplinePositionInterpolator', TSplinePositionInterpolatorNode);
  nodeFactoryMap.Add('SplinePositionInterpolator2D', TSplinePositionInterpolator2DNode);
  nodeFactoryMap.Add('SplineScalarInterpolator', TSplineScalarInterpolatorNode);
  nodeFactoryMap.Add('SpotLight', TSpotLightNode);
  nodeFactoryMap.Add('SquadOrientationInterpolator', TSquadOrientationInterpolatorNode);
  nodeFactoryMap.Add('StaticGroup', TStaticGroupNode);
  { nodeFactoryMap.Add('StreamAudioDestination', TStreamAudioDestinationNode); }
  { nodeFactoryMap.Add('StreamAudioSource', TStreamAudioSourceNode); }
  nodeFactoryMap.Add('StringSensor', TStringSensorNode);
  nodeFactoryMap.Add('SurfaceEmitter', TSurfaceEmitterNode);
  nodeFactoryMap.Add('Switch', TSwitchNode);
  { nodeFactoryMap.Add('TexCoordChaser2D', TTexCoordChaser2DNode); }
  { nodeFactoryMap.Add('TexCoordDamper2D', TTexCoordDamper2DNode); }
  nodeFactoryMap.Add('Text', TTextNode);
  nodeFactoryMap.Add('TextureBackground', TTextureBackgroundNode);
  nodeFactoryMap.Add('TextureCoordinate', TTextureCoordinateNode);
  nodeFactoryMap.Add('TextureCoordinate3D', TTextureCoordinate3DNode);
  nodeFactoryMap.Add('TextureCoordinate4D', TTextureCoordinate4DNode);
  nodeFactoryMap.Add('TextureCoordinateGenerator', TTextureCoordinateGeneratorNode);
  nodeFactoryMap.Add('TextureProjector', TTextureProjectorNode);
  nodeFactoryMap.Add('TextureProjectorParallel', TTextureProjectorParallelNode);
  nodeFactoryMap.Add('TextureProperties', TTexturePropertiesNode);
  nodeFactoryMap.Add('TextureTransform', TTextureTransformNode);
  nodeFactoryMap.Add('TextureTransform3D', TTextureTransform3DNode);
  nodeFactoryMap.Add('TextureTransformMatrix3D', TTextureTransformMatrix3DNode);
  nodeFactoryMap.Add('TimeSensor', TTimeSensorNode);
  nodeFactoryMap.Add('TimeTrigger', TTimeTriggerNode);
  { nodeFactoryMap.Add('ToneMappedVolumeStyle', TToneMappedVolumeStyleNode); }
  nodeFactoryMap.Add('TouchSensor', TTouchSensorNode);
  nodeFactoryMap.Add('Transform', TTransformNode);
  nodeFactoryMap.Add('TransformSensor', TTransformSensorNode);
  nodeFactoryMap.Add('TransmitterPdu', TTransmitterPduNode);
  nodeFactoryMap.Add('TriangleFanSet', TTriangleFanSetNode);
  nodeFactoryMap.Add('TriangleSet', TTriangleSetNode);
  nodeFactoryMap.Add('TriangleSet2D', TTriangleSet2DNode);
  nodeFactoryMap.Add('TriangleStripSet', TTriangleStripSetNode);
  nodeFactoryMap.Add('TwoSidedMaterial', TTwoSidedMaterialNode);
  nodeFactoryMap.Add('UniversalJoint', TUniversalJointNode);
  nodeFactoryMap.Add('UnlitMaterial', TUnlitMaterialNode);
  nodeFactoryMap.Add('Viewpoint', TViewpointNode);
  nodeFactoryMap.Add('ViewpointGroup', TViewpointGroupNode);
  nodeFactoryMap.Add('Viewport', TViewportNode);
  nodeFactoryMap.Add('VisibilitySensor', TVisibilitySensorNode);
  { nodeFactoryMap.Add('VolumeData', TVolumeDataNode); }
  nodeFactoryMap.Add('VolumeEmitter', TVolumeEmitterNode);
  nodeFactoryMap.Add('VolumePickSensor', TVolumePickSensorNode);
  { nodeFactoryMap.Add('WaveShaper', TWaveShaperNode); }
  nodeFactoryMap.Add('WindPhysicsModel', TWindPhysicsModelNode);
  nodeFactoryMap.Add('WorldInfo', TWorldInfoNode);
  nodeFactoryMap.Add('EnvironmentLight', TEnvironmentLightNode);
  nodeFactoryMap.Add('Tangent', TTangentNode);
  { nodeFactoryMap.Add('ImageTextureAtlas', TImageTextureAtlasNode); }
  { nodeFactoryMap.Add('AnisotropyMaterialExtension', TAnisotropyMaterialExtensionNode); }
  nodeFactoryMap.Add('BlendMode', TBlendModeNode);
  { nodeFactoryMap.Add('ClearcoatMaterialExtension', TClearcoatMaterialExtensionNode); }
  { nodeFactoryMap.Add('DepthMode', TDepthModeNode); }
  { nodeFactoryMap.Add('DispersionMaterialExtension', TDispersionMaterialExtensionNode); }
  { nodeFactoryMap.Add('EmissiveStrengthMaterialExtension', TEmissiveStrengthMaterialExtensionNode); }
  { nodeFactoryMap.Add('IORMaterialExtension', TIORMaterialExtensionNode); }
  { nodeFactoryMap.Add('InstancedShape', TInstancedShapeNode); }
  { nodeFactoryMap.Add('IridescenceMaterialExtension', TIridescenceMaterialExtensionNode); }
  { nodeFactoryMap.Add('SheenMaterialExtension', TSheenMaterialExtensionNode); }
  { nodeFactoryMap.Add('SpecularGlossinessMaterial', TSpecularGlossinessMaterialNode); }
  { nodeFactoryMap.Add('SpecularMaterialExtension', TSpecularMaterialExtensionNode); }
  { nodeFactoryMap.Add('TransmissionMaterialExtension', TTransmissionMaterialExtensionNode); }
  { nodeFactoryMap.Add('VolumeMaterialExtension', TVolumeMaterialExtensionNode); }
  { nodeFactoryMap.Add('DiffuseTransmissionMaterialExtension', TDiffuseTransmissionMaterialExtensionNode); }
  
  // X3D statements
  nodeFactoryMap.Add('component', TGroupNode);
  nodeFactoryMap.Add('connect', TGroupNode);
  nodeFactoryMap.Add('EXPORT', TGroupNode);
  nodeFactoryMap.Add('ExternProtoDeclare', TGroupNode);
  nodeFactoryMap.Add('field', TGroupNode);
  nodeFactoryMap.Add('fieldValue', TGroupNode);
  nodeFactoryMap.Add('head', TGroupNode);
  nodeFactoryMap.Add('IMPORT', TGroupNode);
  nodeFactoryMap.Add('IS', TGroupNode);
  nodeFactoryMap.Add('meta', TGroupNode);
  nodeFactoryMap.Add('ProtoBody', TGroupNode);
  nodeFactoryMap.Add('ProtoDeclare', TGroupNode);
  nodeFactoryMap.Add('ProtoInterface', TGroupNode);
  nodeFactoryMap.Add('ROUTE', TGroupNode);
  nodeFactoryMap.Add('Scene', TGroupNode);
  nodeFactoryMap.Add('unit', TGroupNode);
  nodeFactoryMap.Add('X3D', TGroupNode);
  
  // X3D field types
  fieldFactoryMap.Add('SFBool', TSFBool);
  fieldFactoryMap.Add('MFBool', TMFBool);
  fieldFactoryMap.Add('SFColor', TSFColor);
  fieldFactoryMap.Add('MFColor', TMFColor);
  fieldFactoryMap.Add('SFColorRGBA', TSFColorRGBA);
  fieldFactoryMap.Add('MFColorRGBA', TMFColorRGBA);
  fieldFactoryMap.Add('SFDouble', TSFDouble);
  fieldFactoryMap.Add('MFDouble', TMFDouble);
  fieldFactoryMap.Add('SFFloat', TSFFloat);
  fieldFactoryMap.Add('MFFloat', TMFFloat);
  fieldFactoryMap.Add('SFImage', TSFImage);
  { fieldFactoryMap.Add('MFImage', TMFImage); }
  fieldFactoryMap.Add('SFInt32', TSFInt32);
  fieldFactoryMap.Add('MFInt32', TMFInt32);
  fieldFactoryMap.Add('SFMatrix3d', TSFMatrix3d);
  fieldFactoryMap.Add('MFMatrix3d', TMFMatrix3d);
  fieldFactoryMap.Add('SFMatrix3f', TSFMatrix3f);
  fieldFactoryMap.Add('MFMatrix3f', TMFMatrix3f);
  fieldFactoryMap.Add('SFMatrix4d', TSFMatrix4d);
  fieldFactoryMap.Add('MFMatrix4d', TMFMatrix4d);
  fieldFactoryMap.Add('SFMatrix4f', TSFMatrix4f);
  fieldFactoryMap.Add('MFMatrix4f', TMFMatrix4f);
  fieldFactoryMap.Add('SFNode', TSFNode);
  fieldFactoryMap.Add('MFNode', TMFNode);
  fieldFactoryMap.Add('SFRotation', TSFRotation);
  fieldFactoryMap.Add('MFRotation', TMFRotation);
  fieldFactoryMap.Add('SFString', TSFString);
  fieldFactoryMap.Add('MFString', TMFString);
  fieldFactoryMap.Add('SFTime', TSFTime);
  fieldFactoryMap.Add('MFTime', TMFTime);
  fieldFactoryMap.Add('SFVec2d', TSFVec2d);
  fieldFactoryMap.Add('MFVec2d', TMFVec2d);
  fieldFactoryMap.Add('SFVec2f', TSFVec2f);
  fieldFactoryMap.Add('MFVec2f', TMFVec2f);
  fieldFactoryMap.Add('SFVec3d', TSFVec3d);
  fieldFactoryMap.Add('MFVec3d', TMFVec3d);
  fieldFactoryMap.Add('SFVec3f', TSFVec3f);
  fieldFactoryMap.Add('MFVec3f', TMFVec3f);
  fieldFactoryMap.Add('SFVec4d', TSFVec4d);
  fieldFactoryMap.Add('MFVec4d', TMFVec4d);
  fieldFactoryMap.Add('SFVec4f', TSFVec4f);
  fieldFactoryMap.Add('MFVec4f', TMFVec4f);
end;

end.
