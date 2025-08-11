unit X3DJSONLDJava2Pascal;

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
  Classes, SysUtils, DOM, XMLRead, XMLWrite, fpjson, jsonparser, 
  CastleImages, CastleUriUtils,
  CastleInternalNodesUnsupported,
  CastleVectors,
  CastleScene,
  CastleComponentSerialize,
  Generics.Collections, StrUtils, CastleLog, X3DLoad, X3DNodes;

type
  ProtoDictionary = {$ifdef FPC}specialize{$endif} TDictionary<String, TJSONObject>;

type
  TX3DJSONLD = class
  private
    x3dTidy: Boolean;
    protos: ProtoDictionary;
    builtins: TStringList;
    
    function StripQuotes(value: String): String;
    procedure InitializeBuiltins;
    function CommentStringToXML(const str: String): String;
    function NavigationInfoTypeToXML(const str: String): String;
    function FixXML(const str: String; const version: String): String;
    
    procedure ElementSetAttribute(element: TDOMElement; const key: String; 
      const values: TStringList; document: TDOMDocument); overload;
    procedure ElementSetAttribute(element: TDOMElement; const key: String; 
      const value: String; document: TDOMDocument); overload;
    
    function CreateElement(document: TDOMDocument; const key: String; 
      const containerField: String; obj: TJSONObject): TDOMElement;
    
    procedure CDATACreateFunction(document: TDOMDocument; element: TDOMElement; 
      const value: TJSONArray);
    
    procedure ConvertProperty(document: TDOMDocument; const key: String; 
      obj: TJSONObject; element: TDOMElement; const containerField: String);
    
    procedure ConvertJsonObject(document: TDOMDocument; obj: TJSONObject; 
      const parentkey: String; element: TDOMElement; const containerField: String);
    
    procedure ConvertJsonArray(document: TDOMDocument; arr: TJSONArray; 
      const parentkey: String; element: TDOMElement; const containerField: String);
    
    function ConvertJsonValue(document: TDOMDocument; value: TJSONData; 
      const parentkey: String; element: TDOMElement; const containerField: String): TDOMElement;
    
  public
    class var localJSON: TX3DJSONLD;
    constructor Create;
    destructor Destroy; override;
    procedure RegisterJSON;
    function LoadJsonIntoDocument(jsobj: TJSONObject; const version: String; x3dTidyFlag: Boolean): TDOMDocument;
    function ReadJsonFile(const filename: String): TJSONObject;
    function GetX3DVersion(jsobj: TJSONObject): String;
    function SerializeDOM(const x3dVersion: String; document: TDOMDocument): String;
  end;

implementation

constructor TX3DJSONLD.Create;
begin
  inherited Create;
  x3dTidy := False;
  localJSON := Self;
  protos := ProtoDictionary.Create;
  builtins := TStringList.Create;
  builtins.Sorted := True;
  builtins.Duplicates := dupIgnore;
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
  // X3D abstract node types
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
  
  // X3D concrete node types
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
  
  // X3D statements
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
  
  // X3D field types
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

procedure TX3DJSONLD.ElementSetAttribute(element: TDOMElement; const key: String; 
  const values: TStringList; document: TDOMDocument);
var
  sb: String;
  i: Integer;
  fieldValue: TDOMElement;
begin
  sb := '';
  for i := 0 to values.Count - 1 do
  begin
    if i > 0 then
      sb := sb + ' ';
    sb := sb + values[i];
  end;
  
  if key = 'name' then
    element.SetAttribute(key, sb)
  else if (element.TagName = 'ProtoInstance') and (key <> 'DEF') and (key <> 'name') then
  begin
    fieldValue := document.CreateElement('fieldValue');
    fieldValue.SetAttribute('name', key);
    fieldValue.SetAttribute('value', sb);
    element.AppendChild(fieldValue);
  end
  else
    element.SetAttribute(key, sb);
end;

procedure TX3DJSONLD.ElementSetAttribute(element: TDOMElement; const key: String; 
  const value: String; document: TDOMDocument);
var
  fieldValue: TDOMElement;
begin
  if (element.TagName = 'ProtoInstance') and (key <> 'DEF') and (key <> 'name') then
  begin
    fieldValue := document.CreateElement('fieldValue');
    fieldValue.SetAttribute('name', key);
    fieldValue.SetAttribute('value', value);
    element.AppendChild(fieldValue);
  end
  else if key = 'SON schema' then
    // JSON Schema, - ignore
  else if key = 'ncoding' then
    // encoding, UTF-8 - ignore
  else if key = 'xsd:noNamespaceSchemaLocation' then
    // schema, - ignore
  else if key = 'xmlns:xsd' then
    // schema, - ignore
  else if value = '' then
    element.SetAttribute(key, '')
  else begin
    // CastleLog.WriteLnLog('setting field'+key+' to '+value);
    element.SetAttribute(key, StripQuotes(value));
  end;
end;

function TX3DJSONLD.CreateElement(document: TDOMDocument; const key: String; 
  const containerField: String; obj: TJSONObject): TDOMElement;
var
  new_object: TJSONObject;
  child: TDOMElement;
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
  // CastleLog.WritelnLog('Key is '+key);
  if protos.TryGetValue(key, new_object) then begin
    new_key := 'ProtoInstance';
    child := document.CreateElement(new_key);
    child.SetAttribute('name', key);
  end else if (document <> nil) then begin
    child := document.CreateElement(key);
  end else begin
    CastleLog.WritelnLog('Couldn''t find Document root');
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
	  child.SetAttribute('containerField', containerField);
  end;
  
  Result := child;
end;

procedure TX3DJSONLD.CDATACreateFunction(document: TDOMDocument; element: TDOMElement; 
  const value: TJSONArray);
var
  sb: String;
  i: Integer;
  str: String;
  cdata: TDOMCDATASection;
begin
  sb := '';
  for i := 0 to value.Count - 1 do
  begin
    if i > 0 then
      sb := sb + #10;
    str := value.Items[i].AsString;
    str := StringReplace(str, '^"', '', []);
    str := StringReplace(str, '\t', #9, [rfReplaceAll]);
    str := StringReplace(str, '"$', '', []);
    str := StringReplace(str, '&lt;', '<', [rfReplaceAll]);
    str := StringReplace(str, '&gt;', '>', [rfReplaceAll]);
    str := StringReplace(str, '&amp;', '&', [rfReplaceAll]);
    str := StringReplace(str, '&quot;', '"', [rfReplaceAll]);
    sb := sb + str;
  end;
  
  cdata := document.CreateCDATASection(sb);
  element.AppendChild(cdata);
end;

procedure TX3DJSONLD.ConvertProperty(document: TDOMDocument; const key: String; 
  obj: TJSONObject; element: TDOMElement; const containerField: String);
var
  jsonValue: TJSONData;
  arr: TJSONArray;
  i: Integer;
  comment: TDOMComment;
begin
  if not Assigned(obj) then Exit;
  
  jsonValue := obj.Find(key);
  if (jsonValue = nil) then Exit;
  
  if jsonValue is TJSONObject then begin
    if key = '@sourceCode' then
      CDATACreateFunction(document, element, TJSONArray(jsonValue))
    else if (Length(key) > 0) and (key[1] = '@') then
      ConvertJsonValue(document, jsonValue, key, element, containerField)
    else if (Length(key) > 0) and (key[1] = '-') then
      ConvertJsonValue(document, jsonValue, key, element, Copy(key, 2, Length(key)-1))
    else if key = '#comment' then
    begin
      if jsonValue is TJSONArray then
      begin
        arr := TJSONArray(jsonValue);
        for i := 0 to arr.Count - 1 do
        begin
          comment := document.CreateComment(CommentStringToXML(arr.Items[i].AsString));
          element.AppendChild(comment);
        end;
      end
      else
      begin
        comment := document.CreateComment(CommentStringToXML(jsonValue.AsString));
        element.AppendChild(comment);
      end;
    end
    else if key = '#sourceCode' then
      CDATACreateFunction(document, element, TJSONArray(jsonValue))
    else if (key = 'connect') or (key = 'fieldValue') or (key = 'field') or 
            (key = 'meta') or (key = 'component') or (key = 'unit') then
    begin
      arr := TJSONArray(jsonValue);
      ConvertJsonArray(document, arr, key, element, containerField);
    end else  begin
      ConvertJsonValue(document, jsonValue, key, element, containerField);
    end;
  end else begin
 // TODO  else if key = '#comment' then
  end;
end;

function TX3DJSONLD.CommentStringToXML(const str: String): String;
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

function TX3DJSONLD.NavigationInfoTypeToXML(const str: String): String;
begin
  CastleLog.WriteLnLog('X3DJSONLDJava2Pascal jsonstring replacing ', str);
  Result := StringReplace(str, '\', '', [rfReplaceAll]);
  if str <> Result then
    CastleLog.WriteLnLog('with                           ', Result)
  else
    CastleLog.WriteLnLog('ok');
end;

function TX3DJSONLD.FixXML(const str: String; const version: String): String;
begin
  Result := str;
  // Additional XML fixes could be added here if needed
end;

procedure TX3DJSONLD.ConvertJsonObject(document: TDOMDocument; obj: TJSONObject; 
  const parentkey: String; element: TDOMElement; const containerField: String);
var
  kii: Boolean;
  child: TDOMElement;
  i: Integer;
  key: String;
  jsonValue: TJSONData;
  comment: TDOMComment;
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
       (parentkey = 'HAnimJoint') and (element.TagName = 'HAnimHumanoid') then
      tempContainerField := 'joints';
      
    if ((tempContainerField = '') or (tempContainerField = 'coord')) and 
       (parentkey = 'Coordinate') and (element.TagName = 'HAnimHumanoid') then
      tempContainerField := 'skinCoord';
      
    child := Self.CreateElement(document, parentkey, tempContainerField, obj);
  end;
  
  for i := 0 to obj.Count - 1 do
  begin
    key := obj.Names[i];
    jsonValue := obj.Items[i];
    
    if jsonValue is TJSONObject then begin
      if (key = '@type') and (parentkey = 'NavigationInfo') then
        ElementSetAttribute(child, Copy(key, 2, Length(key)-1), 
          NavigationInfoTypeToXML(jsonValue.AsString), document)
      else if (Length(key) > 0) and (key[1] = '@') then
        ConvertProperty(document, key, TJSONObject(jsonValue), child, containerField)
      else if (Length(key) > 0) and (key[1] = '-') then
        ConvertJsonObject(document, TJSONObject(jsonValue), key, child, Copy(key, 2, Length(key)-1))
      else
        ConvertJsonObject(document, TJSONObject(jsonValue), key, child, containerField);
    end else if jsonValue is TJSONArray then
      ConvertJsonArray(document, TJSONArray(jsonValue), key, child, containerField)
    else if jsonValue is TJSONNumber then
      ElementSetAttribute(child, Copy(key, 2, Length(key)-1), jsonValue.AsString, document)
    else if jsonValue is TJSONString then begin
      if key = '#comment' then
      begin
        comment := document.CreateComment(CommentStringToXML(jsonValue.AsString));
        child.AppendChild(comment);
      end
      else if (key = '@type') and (parentkey = 'NavigationInfo') then
        ElementSetAttribute(child, Copy(key, 2, Length(key)-1), 
          NavigationInfoTypeToXML(jsonValue.AsString), document)
      else
        ElementSetAttribute(child, Copy(key, 2, Length(key)-1), jsonValue.AsString, document);
    end else if (jsonValue is TJSONBoolean) then begin
      ElementSetAttribute(child, Copy(key, 2, Length(key)-1), UpperCase(jsonValue.AsString), document);
    end else if (jsonValue is TJSONNull) then begin
      ElementSetAttribute(child, Copy(key, 2, Length(key)-1), jsonValue.AsString, document);
    end;
  end;
  
  if not kii and not ((Length(parentkey) > 0) and (parentkey[1] = '-')) then
    element.AppendChild(child);
end;

procedure TX3DJSONLD.ConvertJsonArray(document: TDOMDocument; arr: TJSONArray; 
  const parentkey: String; element: TDOMElement; const containerField: String);
var
  arrayOfStrings: Boolean;
  localArray: TStringList;
  arraysize, i: Integer;
  jsonValue: TJSONData;
  kii: Boolean;
begin
  if not Assigned(arr) then Exit;
  
  arrayOfStrings := False;
  localArray := TStringList.Create;
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
      
      if jsonValue is TJSONNumber then
        localArray.Add(jsonValue.AsString)
      else if jsonValue is TJSONString then
      begin
        localArray.Add('"'+jsonValue.AsString+'"');
        arrayOfStrings := True;
      end
      else if (jsonValue is TJSONBoolean) or (jsonValue is TJSONNull) then
        localArray.Add(UpperCase(jsonValue.AsString))
      else if jsonValue is TJSONObject then
      begin
        try
          StrToInt(IntToStr(i));
          kii := True;
        except
          kii := False;
        end;
        
        if not ((Length(parentkey) > 0) and (parentkey[1] = '-')) and kii then
          ConvertJsonValue(document, jsonValue, parentkey, element, containerField)
        else
          ConvertJsonValue(document, jsonValue, IntToStr(i), element, Copy(parentkey, 2, Length(parentkey)-1));
      end
      else if jsonValue is TJSONArray then
        ConvertJsonValue(document, jsonValue, IntToStr(i), element, containerField);
    end;
    
    if parentkey = '@sourceCode' then
      CDATACreateFunction(document, element, arr)
    else if (Length(parentkey) > 0) and (parentkey[1] = '@') then
      ElementSetAttribute(element, Copy(parentkey, 2, Length(parentkey)-1), localArray, document)
    else if (parentkey = '#sourceCode') then
      CDATACreateFunction(document, element, arr);
      
  finally
    localArray.Free;
  end;
end;

function TX3DJSONLD.ConvertJsonValue(document: TDOMDocument; value: TJSONData; 
  const parentkey: String; element: TDOMElement; const containerField: String): TDOMElement;
var
  comment: TDOMComment;
begin
  if value is TJSONArray then
    ConvertJsonArray(document, TJSONArray(value), parentkey, element, containerField)
  else
    ConvertJsonObject(document, TJSONObject(value), parentkey, element, containerField);
  
  Result := element;
end;

function TX3DJSONLD.LoadJsonIntoDocument(jsobj: TJSONObject; const version: String; 
  x3dTidyFlag: Boolean): TDOMDocument;
var
  unenversion: String;
  element: TDOMElement;
  doctype: TDOMDocumentType;
  x3dObj: TJSONObject;
begin
  x3dTidy := x3dTidyFlag;
  unenversion := StringReplace(StringReplace(version, '%22', '', [rfReplaceAll]), '"', '', [rfReplaceAll]);
  
  Result := TDOMDocument.Create;
  
  element := Self.CreateElement(Result, 'X3D', '', nil);
  ElementSetAttribute(element, 'xmlns:xsd', 'http://www.w3.org/2001/XMLSchema-instance', Result);
  
  x3dObj := TJSONObject(jsobj.Find('X3D'));
  if Assigned(x3dObj) then
    ConvertJsonObject(Result, x3dObj, '-', element, '');
  
  Result.AppendChild(element);
  
  // Create DOCTYPE - note: Free Pascal's DOM doesn't support creating doctypes the same way
  // This would need to be handled differently in a real implementation
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

function TX3DJSONLD.SerializeDOM(const x3dVersion: String; document: TDOMDocument): String;
var
  stringStream: TStringStream;
begin
  stringStream := TStringStream.Create('');
  try
    WriteXML(document, stringStream);
    Result := stringStream.DataString;
  finally
    stringStream.Free;
  end;
end;

function LoadX3DJsonInternal(const Stream: TStream; const BaseUrl: String): TX3DRootNode; overload;
var
    jsobj: TJSONData;
    document: TDOMDocument;
    XmlStream: TMemoryStream;
    XmlString: String;
begin
  try
  { fileStream := TFileStream.Create(filename, fmOpenRead); }
   XmlStream := TMemoryStream.Create;
   jsobj := GetJSON(Stream);
    if jsobj is TJSONObject then
    begin
      document := TX3DJSONLD.localJSON.LoadJsonIntoDocument(TJSONObject(jsobj), '4.0', False);
      { WriteXMLFile(document, 'output2.x3d'); }
      WriteXML(document, XmlStream);
      XmlStream.Position := 0; // Reset stream position
      SetLength(XmlString, XmlStream.Size);
      XmlStream.Read(XmlString[1], XmlStream.Size);
      XmlStream.Position := 0; // Reset stream position
      { Result := TX3DRootNode.Create }
      Result := LoadNode(XmlStream, '', 'model/x3d+xml');
      SaveNode(Result, 'sampleOutputFromModelViewer.x3d');
    end;
  finally
    XmlStream.Free;
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

end.
