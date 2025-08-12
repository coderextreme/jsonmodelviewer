unit X3DJSONLDX3DNode;

{
  Copyright (c) 2022-2025. John Carlson
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
  X3DFields,
  Classes,
  fpjson, jsonparser,
  CastleImages, CastleUriUtils,
  Generics.Collections,
  X3DNodes,
  X3DLoad;

type
  X3DNodeDictionary = {$ifdef FPC}specialize{$endif} TDictionary<String, TX3DNodeClass>;
  X3DFieldDictionary = {$ifdef FPC}specialize{$endif} TDictionary<String, TX3DFieldClass>;

type
  TX3DJSONLD = class(TObject)
  { TX3DJSONLD = class(TX3DFileItem) }
  private
    x3dTidy: Boolean;

    function getVersion(): TX3DVersion;
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
    procedure SetField(element: TX3DNode; const key: String; const value: TJSONData); overload;

    function CreateElement(const key: String): TX3DNode;
    procedure CDATACreateFunction(element: TX3DNode; const value: TJSONArray);
    procedure ConvertProperty(const key: String; obj: TJSONObject; element: TX3DNode);
    function ConvertJsonObject(obj: TJSONObject; const parentkey: String; element: TX3DNode): TX3DNode;
    procedure ConvertJsonArray(arr: TJSONArray; const parentkey: String; element: TX3DNode);
    procedure ConvertJsonValue(value: TJSONData; const parentkey: String; element: TX3DNode);
    procedure AddChild(parentNode: TX3DNode; childNode: TX3DNode) overload; 
    function JSONArrayToImage(const valueArray: TJSONArray): TCastleImage;
    procedure CreateComment(element: TX3DNode; const arr: String);
    function getKey(originalKey: String): String;
    
  public
    class var localJSON: TX3DJSONLD;
    class var fieldFactoryMap: X3DFieldDictionary;
    class var nodeFactoryMap: X3DNodeDictionary;
    constructor Create;
    destructor Destroy; override;
    procedure RegisterJSON;
    procedure Factory;
    function LoadJsonIntoDocument(jsobj: TJSONObject; x3dTidyFlag: Boolean): TX3DRootNode;
  end;

implementation

uses
  SysUtils,
  StrUtils,
  XMLWrite,
  CastleInternalNodesUnsupported,
  CastleVectors,
  CastleComponentSerialize,
  CastleLog;

type
  TCrackerGrayscaleImage = class(TGrayscaleImage);
  TCrackerGrayscaleAlphaImage = class(TGrayscaleAlphaImage);
  TCrackerRGBImage = class(TRGBImage);
  TCrackerRGBAlphaImage = class(TRGBAlphaImage);

constructor TX3DJSONLD.Create;
begin
  inherited Create;
  x3dTidy := False;
  localJSON := Self;
  nodeFactoryMap := X3DNodeDictionary.Create; 
  fieldFactoryMap := X3DFieldDictionary.Create; 
  Factory;
end;

destructor TX3DJSONLD.Destroy;
begin
  inherited Destroy;
end;

function TX3DJSONLD.getVersion(): TX3DVersion;
begin
	Result := VRML2Version;
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
      for I := 0 to valueArray.Count - 1 do begin
	CastleLog.WriteLnLog('MFInt32 '+IntToStr(I)+' '+valueArray.Items[I].AsJSON);
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
      for I := 0 to valueArray.Count - 1 do begin
      	TMFString(field).Items[I] := valueArray.Items[I].AsString;
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
      for I := 0 to valueArray.Count div 3 do begin
      	TMFVec3f(field).Items[I] := Vector3(
	  valueArray.Items[I*3].AsFloat,
	  valueArray.Items[I*3+1].AsFloat,
	  valueArray.Items[I*3+2].AsFloat);
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

procedure TX3DJSONLD.SetField(element: TX3DNode; const key: String; const value: TJSONData); overload;
var
  keyCopy: String;
  field: TX3DField;
begin
  keyCopy := getKey(key);
  field := GetField(element, keyCopy);
  if (element = nil) and not Assigned(element) then begin
    CastleLog.WriteLnLog('ERROR', 'element is nil in SetField');
  end else if (field = nil) and not Assigned(field) then begin
    CastleLog.WriteLnLog('ERROR', 'field is nil in SetField');
  end else if value is TJSONArray then begin
    ConvertJsonArray(TJSONArray(value), keyCopy, element)
  end else if value is TJSONIntegerNumber then begin
    SetInt32Field(TSFInt32(field), TJSONIntegerNumber(value));
  end else if value is TJSONNumber then begin
    SetDoubleField(TSFDouble(field), TJSONNumber(value));
  end else if value is TJSONFloatNumber then begin
    SetFloatField(TSFFloat(field), TJSONFloatNumber(value));
  end else if value is TJSONInt64Number then begin
    SetInt64Field(TSFInt32(field), TJSONInt64Number(value));
  end else if value is TJSONString then begin
    SetStringField(TSFString(field), TJSONString(value));
  end else if (value is TJSONBoolean) then begin
    SetBoolField(TSFBool(field), TJSONBoolean(value));
  end;
end;

function TX3DJSONLD.CreateElement(const key: String): TX3DNode;
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

procedure TX3DJSONLD.CDATACreateFunction(element: TX3DNode; const value: TJSONArray);
var
  sb: String;
  i: Integer;
begin
  sb := '';
  for i := 0 to value.Count - 1 do
  begin
    if i > 0 then
      sb := sb + #10;
    sb := sb + value.Items[i].AsString;
  end;
  
  { element.CDATAField.Value := sb; }
end;

procedure TX3DJSONLD.CreateComment(element: TX3DNode; const arr: String);
begin
  { TODO  I don'g tknow how to implement this! }
  { AddChild(element, TX3DCommentNode.Create(str)); }
end;

procedure TX3DJSONLD.ConvertProperty(const key: String; obj: TJSONObject; element: TX3DNode);
var
  jsonValue: TJSONData;
  arr: TJSONArray;
  i: Integer;
begin
  if not Assigned(obj) then Exit;
  
  jsonValue := obj.Find(key);
  if not Assigned(jsonValue) then Exit;
  
  if jsonValue is TJSONObject then begin
    if (key = '@sourceCode') or (key = '#sourceCode') then begin
      CDATACreateFunction(element, TJSONArray(jsonValue))
    end else if (Length(key) > 0) and (key[1] = '@') then begin
      ConvertJsonValue(jsonValue, key, element)
    end else if (Length(key) > 0) and (key[1] = '-') then begin
      ConvertJsonValue(jsonValue, key, element)
    end else if key = '#comment' then begin
      if jsonValue is TJSONArray then begin
        arr := TJSONArray(jsonValue);
        for i := 0 to arr.Count - 1 do begin
          CreateComment(element, arr.Items[i].AsString);
        end;
      end else begin
        CreateComment(element, jsonValue.AsString);
      end;
    end else if (key = 'connect') or (key = 'fieldValue') or (key = 'field') or 
            (key = 'meta') or (key = 'component') or (key = 'unit') then begin
      arr := TJSONArray(jsonValue);
      ConvertJsonArray(arr, key, element);
    end else begin
      ConvertJsonValue(jsonValue, key, element);
    end;
  end;
end;

function TX3DJSONLD.ConvertJsonObject(obj: TJSONObject; const parentkey: String; element: TX3DNode): TX3DNode;
var
  kii: Boolean;
  child: TX3DNode;
  I: Integer;
  key: String;
  jsonValue: TJSONData;
begin
  Result := nil;
  if not Assigned(obj) then Exit;
  
  // Check if parentkey is numeric
  try
    StrToInt(parentkey);
    kii := True;
  except
    on E: Exception do
      kii := False;
    on C: EConvertError do
      CastleLog.WriteLnLog('%s: Not a node to create', [ parentkey ])
  end;
  
  if kii or (Length(parentkey) > 0) and (parentkey[1] = '-') then begin
    child := element;
    CastleLog.WriteLnLog('DEBUG', 'Reusing child element');
  end else begin
    CastleLog.WriteLnLog('DEBUG', 'Creating element with %s', [ parentkey ]);
    child := CreateElement(parentkey);
    if (child <> nil) then begin
    	CastleLog.WriteLnLog('DEBUG', 'Created element with %s', [ parentkey ]);
    end else begin
    	CastleLog.WriteLnLog('ERROR', 'Failed to create element with %s', [ parentkey ]);
    end;
  end;
  { if (child = nil) or not(Assigned(child)) then begin
    CastleLog.WriteLnLog('ERROR', 'Problem child for parentkey leading %s key %s', [ parentkey[1], parentkey ]);
    Exit;
  end; }
  
  for i := 0 to obj.Count - 1 do
  begin
    key := obj.Names[i];
    jsonValue := obj.Items[i];
    if key = '#comment' then begin
      CreateComment(child, jsonValue.AsString);
    end else if jsonValue is TJSONObject then begin
      if (Length(key) > 0) and (key[1] = '@') then begin
        ConvertProperty(key, TJSONObject(jsonValue), child)
      end else if (Length(key) > 0) and (key[1] = '-') then begin
        ConvertJsonObject(TJSONObject(jsonValue), key, child)
      end else begin
        ConvertJsonObject(TJSONObject(jsonValue), key, child);
      end;
    end;
  end;
  
  if (not kii) and not ((Length(parentkey) > 0) and (parentkey[1] = '-')) then begin
      AddChild(element, child);
  end;
  Result := child;
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

procedure TX3DJSONLD.ConvertJsonArray(arr: TJSONArray; const parentkey: String; element: TX3DNode);
var
  arraysize, i: Integer;
  jsonValue: TJSONData;
begin
  if not Assigned(arr) then Exit;
  arraysize := arr.Count;
  CastleLog.WriteLnLog('Processing Array: '+ parentkey + ' value is '+arr.AsJSON);
  for i := 0 to arraysize - 1 do
  begin
    jsonValue := arr.Items[i];
    if jsonValue is TJSONArray then begin
      ConvertJsonValue(jsonValue, parentkey, element)
    end else if jsonValue is TJSONObject then begin
      ConvertJsonValue(jsonValue, parentkey, element)
    end else begin
      SetField(element, parentkey, jsonValue);
    end;
  end;
  
  if (parentkey = '@sourceCode') or (parentkey = '#sourceCode') then begin
    CDATACreateFunction(element, arr);
  end else if (Length(parentkey) > 0) and (parentkey[1] = '@') then begin
    SetField(element, parentkey, arr);
  end;
end;

procedure TX3DJSONLD.ConvertJsonValue(value: TJSONData; const parentkey: String; element: TX3DNode);
begin
  if value is TJSONArray then begin
    ConvertJsonArray(TJSONArray(value), parentkey, element)
  end else if value is TJSONObject then begin
    ConvertJsonObject(TJSONObject(value), parentkey, element);
  end else begin
      CastleLog.WriteLnLog('Could not do children of : '+ parentkey + ' value is '+value.AsString);
  end;
end;

function TX3DJSONLD.LoadJsonIntoDocument(jsobj: TJSONObject; x3dTidyFlag: Boolean): TX3DRootNode;
var
	{ element: TX3DNode; }
  x3dObj: TJSONObject;
  child: TX3DNode;
begin
  x3dTidy := x3dTidyFlag;

  Result := TX3DRootNode.Create;
  
  { element := CreateElement('X4D'); }
  
  x3dObj := TJSONObject(jsobj.Find('X3D'));
  if Assigned(x3dObj) then begin
    child := ConvertJsonObject(x3dObj, '-', Result);
    AddChild(Result, child);
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
      Result := TX3DJSONLD.localJSON.LoadJsonIntoDocument(TJSONObject(jsobj), False);
      SaveNode(Result, 'sampleOutputFromModelViewer2.x3d');
    end;
  finally
    jsobj.Free;
  end;
end;

procedure TX3DJSONLD.RegisterJSON();
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

begin
end.
