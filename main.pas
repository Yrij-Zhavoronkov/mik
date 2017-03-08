unit main;

{$mode objfpc}{$H+}


interface


uses
  Classes, SysUtils, FileUtil, SynHighlighterAny, SynEdit, Forms,
  Controls, Graphics, Dialogs, StdCtrls, Menus, Spin, Buttons, Grids, ExtCtrls, Clipbrd, Mik_VM, LZW;


const RAM_count=1024; //1Мб
      command_cl=$b4efc3;
      break_cl=$0000FF;


type  TVisualRAM=record

      RAM:array [0..RAM_count-1] of byte;

      Br_points:array [0..RAM_count-1] of boolean; //Брейк поинты
      U_Numb:array [1..RAM_count] of string[4]; //индексы
      U_Mnem:array [1..RAM_count] of string[4]; //мнемоника
      U_head:array [0..2] of string; //адрес | значение | мнемоника
      end;

       Tcfg_body=record  //config struct
          {bools}
           vars_firstly,clean_mem:boolean;
           hide_win_if_cmp_ok:boolean;
           AutoSet_StartAddr:boolean;
           opimized_calls:boolean;

           MODIFY:boolean; //сейвить или нет?

          {vals}
           addr_shift:word;
           TERM_theme,TERM_W_size,TERM_W_theme:byte;
       end;

var


   //Registers
   { RA:word;         //рег адреса
    RK:byte;         //Рег команды
    RW:shortint;     //Рег признака
    RS,R1:Smallint;   //Сумматор / рабочий  //EXPEREMENTAL}

    MikCPU:TMikCpu;

    run,pause:boolean;

    V_RAM:TVisualRAM;

    app_config:Tcfg_body; //глоб конфиг
    config_folder,config_file:UTF8String;

type

  { Tmain_gui }

  Tmain_gui = class(TForm)
    data_in: TEdit;
    data_p1: TEdit;
    data_p2: TEdit;

    mem_gui: TDrawGrid;
    MenuItem11: TMenuItem;
    MenuItem12: TMenuItem;
    cp_code: TMenuItem;
    MenuItem13: TMenuItem;
    MenuItem14: TMenuItem;
    MenuItem15: TMenuItem;
    MenuItem8: TMenuItem;
    MenuItem9: TMenuItem;
    PopupMenu1: TPopupMenu;
    r_gui_img: TImageList;
    Log_style: TSynAnySyn;
    cmdEnter: TBitBtn;
    save_dump: TBitBtn;
    dataEnter: TBitBtn;
    MainMenu1: TMainMenu;
    MenuItem1: TMenuItem;
    MenuItem10: TMenuItem;
    MNext: TMenuItem;
    MStop: TMenuItem;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    MenuItem4: TMenuItem;
    MenuItem5: TMenuItem;
    MenuItem6: TMenuItem;
    MenuItem7: TMenuItem;
    mRun: TMenuItem;
    MRun_by_step: TMenuItem;
    OD: TOpenDialog;
    reg_7: TSpinEdit;
    SD: TSaveDialog;
    Ch_mode: TSpeedButton;
    stop_exec: TBitBtn;
    Run_code: TBitBtn;
    run_by_steps: TBitBtn;
    next_step: TBitBtn;
    CleanRegisters: TBitBtn;
    BitBtn7: TBitBtn;
    open_dump: TBitBtn;
    New_dump: TBitBtn;
    verb: TCheckBox;
    r_sum: TEdit;
    R_pr: TEdit;
    R_addr: TEdit;
    R_cmd: TEdit;
    R_work: TEdit;
    reg_6: TComboBox;
    RegPanel: TGroupBox;
    GroupBox2: TGroupBox;
    Data_inp: TGroupBox;
    GroupBox4: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label8: TLabel;
    reg_5: TSpinEdit;
    ScrollBox1: TScrollBox;
    log: TSynEdit;
    procedure dataEnterClick(Sender: TObject);
    procedure data_inKeyPress(Sender: TObject; var Key: char);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure mem_guiDblClick(Sender: TObject);
    procedure mem_guiDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure mem_guiSelection(Sender: TObject; aCol, aRow: Integer);
    procedure cp_codeClick(Sender: TObject);
    procedure MenuItem7Click(Sender: TObject);
    procedure mRunClick(Sender: TObject);
    procedure MRun_by_stepClick(Sender: TObject);
    procedure PopupMenu1Popup(Sender: TObject);
    procedure save_dumpClick(Sender: TObject);
    procedure cmdEnterClick(Sender: TObject);
    procedure CleanRegistersClick(Sender: TObject);
    procedure BitBtn7Click(Sender: TObject);
    procedure open_dumpClick(Sender: TObject);
    procedure New_dumpClick(Sender: TObject);
    procedure data_0Exit(Sender: TObject);
    procedure data_p1KeyPress(Sender: TObject; var Key: char);
    procedure data_p2KeyPress(Sender: TObject; var Key: char);
    procedure MNextClick(Sender: TObject);
    procedure MStopClick(Sender: TObject);
    procedure next_stepClick(Sender: TObject);
    procedure Run_codeClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Ch_modeClick(Sender: TObject);
    procedure stop_execClick(Sender: TObject);
  private
    procedure load_config;

  public
    grid_buf:Tbitmap;
    arc_ram_gui:array [0..1] of Tbitmap;
    procedure save_config;

end;

var
  main_gui: Tmain_gui;

implementation

uses asm_comp,xterm_gui,xterm_core,        mik_asm_compiller;


{$R *.lfm}

{ Tmain_gui }

{cfg utils}
procedure set_defaults;
begin
  with app_config do
  begin
     vars_firstly:=true;
     clean_mem:=true;
     hide_win_if_cmp_ok:=false;
     AutoSet_StartAddr:=true;
     opimized_calls:=true;

     {vals}
     addr_shift:=0;
     TERM_theme:=3;
     TERM_W_size:=0;
     TERM_W_theme:=3;
  end;
end;

procedure set_val(prm:string);
var
  nm,value:string;
  k:integer;
begin
  prm:=uppercase(prm);

  if length(prm) in [10..25] then
     begin
       nm:=copy(prm,1,pos('=',prm)-1);
       delete(prm,1,pos('=',prm));
       value:=trim(prm);

     with app_config do
       case nm of
           'CLEAN_MEM' :clean_mem:=(value='TRUE');
           'VARS_FIRST':vars_firstly:=(value='TRUE');
           'AUTOSET_ADDR':AutoSet_StartAddr:=(value='TRUE');
           'HIDE_WINDOW_IF_COMP':hide_win_if_cmp_ok:=(value='TRUE');
           'OPTIMIZE_CALLS':opimized_calls:=(value='TRUE');

           'ADDR_SHIFT':if (tryStrToint(value,k) and (k>-1) and (k<65500))
                                    then addr_shift:=k;

           'TERM_THEME':if ((tryStrToint(value,k)) and (k in [0..3]))
                                    then TERM_theme:=k;

           'TERM_W_SIZE':if ((tryStrToint(value,k)) and (k in [0..3]))
                                    then TERM_W_size:=k;
       end;
     end;
end;

procedure Tmain_gui.load_config;
var
  cfg_f:text;
  buf:string;
begin
  set_defaults; //по умолчанию / инициализация


  if fileExists(config_file) then
     begin
        assignFile(cfg_f,config_file);
        reset(cfg_f);

        while (not EOF(cfg_f)) do
          begin
            readln(cfg_f,buf);
            set_val(trim(buf));
          end;

        closefile(cfg_f);
        app_config.MODIFY:=false;
     end;
end;

procedure Tmain_gui.save_config;
var
   cfg_f:text;
   dir_ok:boolean;
begin
  if app_config.MODIFY then
  begin
       dir_ok:=true;
       {check paths}
       if not (DirectoryExists(config_folder)) then
              dir_ok:=CreateDir(config_folder);



       if (dir_ok) then
          with app_config do
          begin
               //save to file
               assignfile(cfg_f,config_file);
               rewrite(cfg_f);

               writeln(cfg_f,'CLEAN_MEM=',clean_mem);
               writeln(cfg_f,'VARS_FIRST=',vars_firstly);
               writeln(cfg_f,'AUTOSET_ADDR=',AutoSet_StartAddr);
               writeln(cfg_f,'HIDE_WINDOW_IF_COMP=',hide_win_if_cmp_ok);
               writeln(cfg_f,'OPTIMIZE_CALLS=',opimized_calls);

               writeln(cfg_f,'ADDR_SHIFT=',addr_shift);
               writeln(cfg_f,'TERM_THEME=',TERM_theme);
               writeln(cfg_f,'TERM_W_SIZE=',TERM_W_size);

               closefile(cfg_f);
               modify:=false;
          end;
   end;
end;
{end cfg utils}

procedure Tmain_gui.FormCreate(Sender: TObject);
var
  int:word;
begin
  grid_buf:=Tbitmap.Create;
  grid_buf.Width:=115;
  grid_buf.Height:=16;

  grid_buf.Canvas.Pen.Color:=clwhite;
  for int:=0 to 8 do begin
  grid_buf.Canvas.Line(0,int,115,int);
  grid_buf.Canvas.Pen.Color:=grid_buf.Canvas.Pen.Color-$050505;
  end;
  for int:=8 to 16 do begin
  grid_buf.Canvas.Line(0,int,115,int);
  grid_buf.Canvas.Pen.Color:=grid_buf.Canvas.Pen.Color+$050505;
  end;

  application.ProcessMessages;

  arc_ram_gui[0]:=Tbitmap.Create;
  arc_ram_gui[1]:=Tbitmap.Create;
  r_gui_img.GetBitmap(0,arc_ram_gui[0]);
  r_gui_img.GetBitmap(1,arc_ram_gui[1]);

  freeandNil(r_gui_img);

  mem_gui.RowCount:=RAM_count+1;

  for int:=0 to RAM_count-1 do
  case int of
     000..009:V_RAM.U_Numb[int+1]:='000'+inttostr(int);
     010..099:V_RAM.U_Numb[int+1]:='00'+inttostr(int);
     100..999:V_RAM.U_Numb[int+1]:='0'+inttostr(int);
     else V_RAM.U_Numb[int+1]:=inttostr(int);
  end;

  v_ram.U_head[0]:='Адрес';
  mem_gui.ColWidths[0]:=54;

   v_ram.U_head[1]:='Значение (DEC)';
  mem_gui.ColWidths[1]:=115;

   v_ram.U_head[2]:='Мнемоника';
  mem_gui.ColWidths[2]:=100; //105

  mem_gui.Canvas.Font.Name:='Verdana';
  mem_gui.Canvas.Font.Size:=8;

  clean_mem; //ini mem

  mem_gui.Width:=294;

  {SET PATHS}
   {$IFDEF UNIX}
              config_folder:=GetEnvironmentVariableUTF8('HOME')+'/.mik2';
              config_file:=config_folder+'/mik_config.cfg';
   {$ELSE}
         {widows}

              config_folder:=GetEnvironmentVariableUTF8('temp'); //здесь точно есть права у ВСЕХ пользователей
              config_file:=config_folder+'\mik_config.cfg';
   {$ENDIF}

  //грузи конфиг
  load_config;
end;

procedure Tmain_gui.Ch_modeClick(Sender: TObject);
begin
    data_p1.visible:=ch_mode.Down;
    data_p2.visible:=ch_mode.Down;
    data_in.visible:=not ch_mode.Down;
end;

procedure Tmain_gui.stop_execClick(Sender: TObject);
begin

  MikCpu.Proc_HaltQuery;
  main_gui.log.Lines.Add(TIMETOSTR(time())+' Выполнение прервано пользователем');
end;

procedure Tmain_gui.cmdEnterClick(Sender: TObject); //CRITICAL FIX
var
  adr:word;
  code_len,cmd:byte;
  AXH,AXL:byte; //addon data
  int_val:longint;

  //interface
  background_cl:TColor;
begin
 //дай то, что ввел там пользователь
 Get_RegValue_from_gui(AXH, AXL, int_val);

 adr:=reg_5.value;

 case reg_6.ItemIndex of
     00:begin cmd:=01;  code_len:=1; end;
     01:begin cmd:=02;  code_len:=1; end;
     02:begin cmd:=10;  code_len:=3; end;
     03:begin cmd:=11;  code_len:=3; end;
     04:begin cmd:=12;  code_len:=3; end;
     05:begin cmd:=21;  code_len:=3; end;
     06:begin cmd:=22;  code_len:=3; end;
     07:begin cmd:=23;  code_len:=3; end;
     08:begin cmd:=30;  code_len:=3; end;
     09:begin cmd:=33;  code_len:=3; end;
     10:begin cmd:=34;  code_len:=3; end;
     11:begin cmd:=99;  code_len:=1; end;
  end;

 //проверка диапазона...
 if (code_len=3) and ((int_val<0) or (int_val>$FFFF)) then code_len:=0; //0 - выход

  case code_len of
      1:v_RAM.RAM[adr]:=cmd;
      3:begin
        v_RAM.RAM[adr]:=cmd;
        v_RAM.RAM[adr+1]:=AXH;
        v_RAM.RAM[adr+2]:=AXL;
        end;
  end;

 {refresh interface}
 if code_len>0 then
 begin
    inc(adr,code_len);
    reg_5.value:=adr;
    mem_gui.tag:=1; {блокир 2-го изменения индекса, костыль}
      mem_gui.Row:=adr+1;
    mem_gui.tag:=0;
    background_cl:=clDefault; //из темы
 end else background_cl:=$6060ff; //розовый для ошибки


    case data_in.Visible of
       true:data_in.Color:=background_cl;
       false:begin
                  data_p1.Color:=background_cl;
                  data_p2.Color:=background_cl;
             end;
    end;
end;

procedure Tmain_gui.save_dumpClick(Sender: TObject);
var
  f:TFileStream;
  int,len,addr:word;
  zero_ct:byte;
  IO_error, addr_overflow:boolean;
  label rs_loop;
begin
 {preload}
 if SD.FileName='' then SD.FileName:=OD.FileName;
 {execute}
 if SD.Execute then  begin
  {******************************************************
  SINGATURE = 6Bytes
  ADDRESS SHIFT = 1 Byte  (max 512) (IMPORTANT!! BLOCK SIZE = 2Bytes)
  DATA LENGTH = 1 Byte;   (max 512)
  DATA
  ******************************************************}
  IO_error:=false;
TRY
   f:=TFilestream.Create(SD.FileName, fmCreate);

     log.Lines.Add('===================');
     log.Lines.Add('Сохранить дамп памяти в файл: '+extractFileName(SD.FileName));

  if uppercase(extractfileExt(sd.FileName))<>'.MDMP'
     then sd.FileName:=extractfilename(sd.FileName)+'.MDMP';

  {пишем сигнатуру}
  f.WriteWord($444D); f.WriteWord($6D75); f.WriteWord($0270);

  {analyze loop}
       addr:=0;
rs_loop:int:=0;
        while (int+addr<RAM_count) and (V_RAM.RAM[int+addr]=0) do inc(int);

        if int+addr<RAM_count then
        begin
             {OWERFLOW PROTECT! 29.01.15}
             addr_overflow:=int>510;
             if addr_overflow
                    then int:=510;
             {END}

             //working
             //пишем сдвиг (в блоках)
             f.WriteByte(int div 2);
             int:=(int div 2)*2;

             len:=0;
             zero_ct:=0;

             {upd addr}
             inc(addr,int);
             int:=addr;

         if not addr_overflow then {? искать длинну}
                  while (int<RAM_count) and (zero_ct<3) do  //допускается 2 нуля подряд = 1 блока
                  begin
                       if V_RAM.RAM[int]=0
                          then inc(zero_ct)
                          else begin
                                    inc(len);
                                    zero_ct:=0;
                               end;
                       inc(int);
                  end;

             //пишем длинну (в блоках) [len]+1
             len:=(len mod 2)+(len div 2);
             f.WriteByte(len);
             len:=len*2;

             //пишем len байт, если надо...
          if not addr_overflow then
                 for int:=0 to len-1 do f.writeByte(V_RAM.RAM[int+addr]);

             inc(addr,len); //upd addr
             goto rs_loop;
        end;

EXCEPT
  IO_error:=true;
end;
            //else nothing to do.....
  {end loop}

  if IO_error then log.Lines.Add('Не удалось записать дамп памяти в файл, возможно нет места или доступ ограничен')
              else log.Lines.Add('Дамп успешно сохранен.');

      log.Lines.Add('===================');
  f.Free;
 end;
end;

procedure Tmain_gui.mem_guiDrawCell(Sender: TObject; aCol, aRow: Integer;
  aRect: TRect; aState: TGridDrawState);
begin
  //draw interface
  //сперва пороверка для мемоники.
 with mem_gui do
  if arow>0 then
  begin
       case v_RAM.RAM[arow-1] of
           01:v_ram.U_Mnem[aRow]:='IN';
           02:v_ram.U_Mnem[aRow]:='OUT';
           10:v_ram.U_Mnem[aRow]:='ADD';
           11:v_ram.U_Mnem[aRow]:='SUB';
           12:v_ram.U_Mnem[aRow]:='CMP';
           21:v_ram.U_Mnem[aRow]:='LD';
           22:v_ram.U_Mnem[aRow]:='ST';
           23:v_ram.U_Mnem[aRow]:='LA';
           30:v_ram.U_Mnem[aRow]:='JMP';
           33:v_ram.U_Mnem[aRow]:='JZ';
           34:v_ram.U_Mnem[aRow]:='JM';
           99:v_ram.U_Mnem[aRow]:='HALT'
           else v_ram.U_Mnem[aRow]:='-';
       end;

  //готовим фон..
     canvas.Brush.Style:=bsSolid;
  if v_ram.Br_points[arow-1] then  //breakpoint!!
  begin
       Canvas.Pen.Color:=break_cl;
       canvas.brush.Color:=break_cl;
       canvas.Rectangle(arect);
  end
    else
  if length(v_ram.U_Mnem[aRow])>1 then
    begin
       Canvas.Pen.Color:=command_cl;
       canvas.brush.Color:=command_cl;
       canvas.Rectangle(arect);
    end else canvas.Clear;

  //фон готов
    canvas.Brush.Style:=bsClear;
    canvas.font.Bold:=false;
  case acol of
      0:begin
      canvas.font.Bold:=true;
      canvas.TextOut(arect.right-canvas.textwidth(v_ram.U_Numb[aRow])-3,arect.Top,v_ram.U_Numb[aRow]);

      //если выделен
       if aRow=row then
        canvas.Draw(arect.left,arect.Top,arc_ram_gui[1]) else
      //если брейк...
      if v_ram.Br_points[arow-1] then
        canvas.Draw(arect.left,arect.Top,arc_ram_gui[0]);

      end;  //номер по правому краю!!!
      1:canvas.TextOut(arect.left+(ColWidths[1]- canvas.textWidth(inttostr(v_RAM.RAM[aRow-1]))) div 2,arect.Top,inttostr(v_RAM.RAM[aRow-1]));  //данные из памяти
      2:canvas.TextOut(arect.left+(ColWidths[2]- canvas.textWidth(v_ram.U_Mnem[arow])) div 2,arect.Top,v_ram.U_Mnem[arow]); //мемоника
  end;
  end else
      begin  //для заголовков
          canvas.Draw(arect.left,arect.Top,grid_buf);
          canvas.font.Bold:=false;
          canvas.Brush.Style:=bsclear;
          canvas.TextOut(arect.left+(ColWidths[acol]- canvas.textWidth(v_ram.U_head[aCol])) div 2,arect.Top,v_ram.U_head[aCol]);
     end;
 end;

procedure Tmain_gui.mem_guiDblClick(Sender: TObject);
begin
  //set break point
 v_ram.Br_points[mem_gui.Row-1]:=not v_ram.Br_points[mem_gui.Row-1];
end;

procedure Tmain_gui.dataEnterClick(Sender: TObject);
var
  adr:word;
  AXH,AXL:byte; //addon data
  int_val:longint;
begin
 GET_RegValue_from_gui(AXH, AXL, int_val);

 adr:=reg_5.value;

  v_RAM.RAM[adr]:=AXH;
  v_RAM.RAM[adr+1]:=AXL;
  inc(adr,2);

 reg_5.value:=adr;
 mem_gui.Tag:=1;  //блокир 2-го изменения индекса
 mem_gui.Row:=adr+1;
 mem_gui.Tag:=0; //норм
end;

procedure Tmain_gui.data_inKeyPress(Sender: TObject; var Key: char);
begin
  if data_in.text='0' then data_in.text:='';
  if data_in.text='' then begin
   if not (key in ['0'..'9',#8,'-']) then key:=#0;
  end
  else
  if not (key in ['0'..'9',#8]) then key:=#0;
end;

procedure Tmain_gui.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
   //сохр конфиг
   save_config;
end;

procedure Tmain_gui.mem_guiSelection(Sender: TObject; aCol, aRow: Integer);
begin
  if mem_gui.Tag=0 then
    reg_5.value:=mem_gui.Row-1;
    repaint;
end;

procedure Tmain_gui.cp_codeClick(Sender: TObject);
var
  point:word;
  len:byte;
  buf:wideString;
begin
 point:=reg_5.Value;
 buf:='';

 //start = RA
 while (point<RAM_count) and (get_typeOfCommand(v_RAM.RAM[point])>0) do
 begin
    buf:=buf+format_outp(inttostr(point),4)+') '+format_outp(inttostr(v_RAM.RAM[point]),2);
    len:=1;

    if not (v_RAM.RAM[point] in [1,2,99]) then
       if point+2<RAM_count then //EOF protect
           begin
             len:=3;
             buf:=buf+' '+format_outp(inttostr(v_RAM.RAM[point+1]*256+v_RAM.RAM[point+2]),4);
           end;

    buf:=buf+';'+#13;
    inc(point,len);
 end;

  //сборка в буфер
  Clipboard.asText:=buf;
end;

procedure Tmain_gui.MenuItem7Click(Sender: TObject);
begin
  close;
end;

procedure Tmain_gui.mRunClick(Sender: TObject);
begin
  run_code.Click
end;

procedure Tmain_gui.MRun_by_stepClick(Sender: TObject);
begin
   run_by_steps.Click;
end;

procedure Tmain_gui.PopupMenu1Popup(Sender: TObject);
begin
  //check code
  cp_code.Enabled:=not (get_typeOfCommand(v_RAM.RAM[reg_5.Value])=0);
end;

procedure Tmain_gui.CleanRegistersClick(Sender: TObject);
begin
    r_sum.Text:='0';
    r_pr.Text:='0';
    r_addr.Text:='0';
    r_cmd.Text:='0';
    r_work.Text:='0';
end;

procedure Tmain_gui.BitBtn7Click(Sender: TObject);
begin
  asm_code.Show;
end;

procedure Tmain_gui.open_dumpClick(Sender: TObject);
var
  //f:TMemorystream;
  F:TFileStream;
  int,addr,len:word;
  map:array [1..3] of word;
  valid_format:boolean;
  return_code:byte;
begin
 {preload}
 if OD.FileName='' then OD.FileName:=SD.FileName;
 {execute}
 if OD.Execute then
begin
  f:=TFilestream.Create(OD.FileName, fmOpenRead);
     log.Lines.Add('===================');
     log.Lines.Add('Загрузить дамп памяти из файла: '+extractFileName(OD.FileName));

  valid_format:=false;
  return_code:=0;
  if f.Size>5 then
  begin
      f.Read(map,6);
      valid_format:=(map[1]=$444D) and (map[2]=$6D75) and (map[3]=$0270);
  end;

  try
  //валидация успешна.. начинаем
  if valid_format then
  begin
   clean_mem; //Clean RAM
   int:=0;
   addr:=0;

     while f.Position<f.Size do
     begin
       //чит сдвиг и длинну
       inc(addr, f.readByte*2); //ACHTUNG!! block size=2B
       len:=f.readByte*2;

       for int:=0 to len-1 do
           if int+addr<RAM_count then
               V_RAM.RAM[int+addr]:=f.readByte;

       inc(addr,len); //upd addr
     end;
  end else return_code:=1;

  Except
     //что сказать? повреждение файла!)
        return_code:=2;
  end;

  f.free;

  case return_code of
      1:log.Lines.Add('Ошибка: Неверный формат файла или файл поврежден ');
      2:log.Lines.Add('Файл поврежден, загрузка прервана. ');
      0:log.Lines.Add('Дамп успешно загружен. ');
  end;
  log.Lines.Add('===================');

  mem_gui.Repaint;
end;
end;

procedure Tmain_gui.New_dumpClick(Sender: TObject);
begin
  clean_mem;
  mem_gui.Repaint;
end;

procedure Tmain_gui.data_0Exit(Sender: TObject);
begin
     with sender as TEdit do
  if text='' then text:='0';
end;

procedure Tmain_gui.data_p1KeyPress(Sender: TObject; var Key: char);
begin
  with sender as TEdit do
  if text='0' then text:='';
  if not (key in ['0'..'9',#8]) then key:=#0;
end;

procedure Tmain_gui.data_p2KeyPress(Sender: TObject; var Key: char);
begin
 with sender as TEdit do
  if text='0' then text:='';
   if not (key in ['0'..'9',#8]) then key:=#0;
end;

procedure Tmain_gui.MNextClick(Sender: TObject);
begin
  next_step.Click;
end;

procedure Tmain_gui.MStopClick(Sender: TObject);
begin
  stop_exec.Click;
end;

procedure Tmain_gui.next_stepClick(Sender: TObject);
begin
 //pause:=false;
 if (MikCpu<>nil) then MikCpu.Resume else showmessage('Произошла непредвиденая ошибка');
end;

procedure Tmain_gui.Run_codeClick(Sender: TObject);
begin
   if  (MikCPU=nil) then
      begin
      //showmessage('nil');
       MikCPU:=TMikCPU.Create(true); //ВМ не запущена.. создай поток suspended

       {GUI}
         //заблокируем ввод данных
         Data_inp.Enabled:=false;
         R_addr.ReadOnly:=true;

         //Кнопки...
         {блокир}
         //run_code.Enabled:=false;
         //mRun.Enabled:=false;
         //run_by_steps.Enabled:=false;
         //MRun_by_step.Enabled:=false;
         next_step.Enabled:=false;
         MNext.Enabled:=false;

         {разблок}
         stop_exec.Enabled:=true;
         MStop.Enabled:=true;


         //очистка лога
         log.Lines.Clear;
         log.Lines.Add(TIMETOSTR(time())+' Старт ВМ...');

         clean_term(true);
         if not term.Showing then term.Show;
       {End GUI}
      end;


   {блокир}
   run_code.Enabled:=false;
   mRun.Enabled:=false;

   run_by_steps.Enabled:=false;
   MRun_by_step.Enabled:=false;
   {end}

    //set метод работы CPU
    with sender as TBitBtn do
    MikCPU.single_run_mode:=(name='run_by_steps');

    //запуск
    MikCPU.Resume;
 end;

end.

