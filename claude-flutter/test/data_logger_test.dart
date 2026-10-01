import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_detector/services/data_logger.dart';
List<String> cells(String row) => row.substring(1,row.length-1).split('","');
void main(){
 test('native CSV retains real measurements, missing values and escaped flags',()async{
  final directory=await Directory.systemTemp.createTemp('ghost_logger_test');
  final logger=DataLogger(directory:()async=>directory);await logger.start();
  logger.add(mag:null,magAnomaly:false,mode:'measure',ghost:null,vib:0,motion:0,tilt:0,heading:0,ghostDistance:null,mood:null);
  logger.add(mag:const MagRow(x:24,y:32,z:0,total:40,baseline:39,delta:1,sigma:.2,threshold:4,accuracy:'high',source:'test_sensor'),magAnomaly:false,mode:'measure',ghost:null,vib:.1,motion:.05,tilt:.2,heading:90,ghostDistance:null,mood:null);
  logger.manualFlag('日本語, Монгол "test"');
  final file=await logger.flush();expect(file,isNotNull);
  final rows=(await file!.readAsString()).split('\n').where((s)=>s.isNotEmpty).toList();expect(rows.length,4);
  final missing=cells(rows[1]),real=cells(rows[2]);expect(missing.length,DataLogger.header.length);expect(missing[3],'unavailable');expect(missing[8],'');expect(missing[17],'');expect(real[3],'test_sensor');expect(real[8],'40.00');expect(real[14],'5.0');expect(real[17],'');expect(real[18],'');expect(real[19],'');expect(rows[3],contains('日本語, Монгол ""test""'));
  logger.dispose();await Future<void>.delayed(const Duration(milliseconds:30));await directory.delete(recursive:true);
 });
}
