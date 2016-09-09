# Removes all of the files in a given resource
#
# INPUT PARAMETERS:
#   Resc - The resource containing the files to be removed.
rmResc {
  foreach(*row in SELECT COLL_NAME, DATA_NAME WHERE RESC_NAME = *Resc) {
    *objPath = *row.COLL_NAME ++ '/' ++ *row.DATA_NAME;
    msiDataObjTrim(*objPath, *Resc, "null", "1", "admin", *out);
    if (*out == 0) {
      msiDataObjUnlink("objPath=*objPath++++forceFlag=", *out);
    }
  }
}
INPUT *Resc="demoResc"
OUTPUT ruleExecOut
