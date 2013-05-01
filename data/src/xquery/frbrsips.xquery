module namespace frbr = "http://perseus.org/xquery/frbr";

declare namespace mods="http://www.loc.gov/mods/v3";
declare namespace cts="http://chs.harvard.edu/xmlns/cts3/ti";
declare namespace atom="http://www.w3.org/2005/Atom";
declare namespace dc = "http://purl.org/dc/elements/1.1/";
declare namespace xsi ="http://www.w3.org/2001/XMLSchema-instance";
declare namespace saxon="http://saxon.sf.net/";
declare namespace existtx="http://exist-db.org/xquery/transform";

declare variable $e_collection as xs:string external;
declare variable $e_ids as xs:string external;
declare variable $e_idTypes as xs:string external;
declare variable $e_lang as xs:string external;
declare variable $e_authorUrl as xs:string external;
declare variable $e_authorId as xs:string external;
declare variable $e_authorNames as xs:string external;
declare variable $e_titles as xs:string* external;
declare variable $e_perseus as xs:string external;
declare variable $e_updateDate as xs:string external;

declare variable $frbr:e_pidBase := 'http://data.perseus.org/catalog/'; 


declare function frbr:make_sip($a_collection as xs:string, $a_lang as xs:string,$a_id as xs:string, $a_mods as node()*,$a_related as node()*,$a_titles as xs:string,$a_updateDate) as node()
{        
        let $ns := if ($a_lang = 'grc') then "greekLit" else "latinLit"
        let $ctsplus := frbr:make_cts($a_lang,$a_id,$a_mods,$ns,$a_titles)
        return
        element atom:feed {
           element atom:id { concat($frbr:e_pidBase,'urn:cts:',$ns,':',$a_id,'/atom') },
            element atom:updated {$a_updateDate},
            element atom:entry {
                element atom:id { concat($frbr:e_pidBase,'urn:cts:',$ns,':',$a_id,'/atom#ctsti') },
                (: add external data streams for the XML content unless under copyright :)
                (: TODO PUT THIS BACK IN WHEN WE ARE READY TO PUBLISH TEXT LINKS?? WHAT IS THE FINAL LOCATION ?? :)
                (:
                for $online at $a_i in 
                	$ctsplus//cts:*[cts:memberof[not(contains(@collection,'-protected'))]]/cts:online return                    
                    let $docname := $online/@docname
                    let $projid := if (matches($online/parent::*/@projid,':')) then 
                        substring-after($online/parent::*/@projid,':') else $online/parent::*/@projid 
                    let $id := 
                        concat('urn:cts:',$ns,':',$a_id,'.',$projid)
                    let $url := concat('http://www.perseus.tufts.edu/hopper/opensource/downloads/texts/tei/',$docname[1])
                    return 
                        element atom:link {
                            attribute id { concat('TEI.',$docname[1]) }, 
                            attribute href { $url },
                            attribute type { 'text/xml' },
                            attribute rel { 'self' }
                        },
                  :)
                    element atom:content{
        				attribute type { "text/xml" },                           
        				frbr:exclude-mods($ctsplus)
        			} (: end CTS content element :)
        			(:if ($ctsplus//refindex) then
        				element atom:content{
        			     	attribute type { "text/xml" },
        				    $ctsplus//refindex                                              
        				} (: end content element :)
        			else ()
        	     :)
            }, (: end entry element :)
            for $edition at $a_i in $ctsplus//mods:mods[mods:identifier[@type="ctsurn"]] return
                element atom:entry {
                    element atom:id { concat($frbr:e_pidBase,$edition/mods:identifier[@type="ctsurn"][1],'/atom#mods') },
            	    element atom:content{
                            attribute type { "text/xml" },
                            $edition                                             
                	} (: end MODS content element :)
                }, (: end entry element :)
              for $related at $a_i in $a_related return
                element atom:entry {
                    element atom:id { concat($frbr:e_pidBase, $ns, ':',$a_id, '/atom#mods-relateditem-',$a_i)},
            	    element atom:content{
                            attribute type { "text/xml" },
                            element mods:mods {
                                attribute xsi:schemaLocation { "http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-4.xsd" },
                                for $node in $related/*
                                return
                                    if ( node-name($node) = QName("http://www.loc.gov/mods/v3","identifier")) 
                                    then frbr:normalize_display_label($node)
                                    else $node
                            }
                	} (: end MODS content element :)
                } (: end entry element :)
        }     (: end feed element :)        
};

declare function frbr:exclude-mods($a_nodes as node()*) as node()*
{
    for $node in $a_nodes return 
        if (node-name($node) = QName("http://www.loc.gov/mods/v3","mods") or 
            node-name($node) = QName("","refindex"))            
        then ()
        else if ($node instance of element()) then
            element { node-name($node) } {
                $node/@*,
                frbr:exclude-mods($node/node())
            }
        else 
            $node              
};

declare function frbr:make_id($a_id as xs:string, $a_type as xs:string) as xs:string {
    if ($a_type = 'tlg' or $a_type = 'phi')
    then 
        let $parts := tokenize($a_id,"\.")
        let $combined := for $part in $parts return concat($a_type,$part)
        return string-join($combined,".")
    else
    if ($a_type = 'tlg_frag') then
        let $temp := 
            if (matches($a_id,'x?-','i')) then replace($a_id,'-','.')
            else if (matches($a_id,'x','i')) then replace($a_id,'x','.X','i')
            else $a_id
        let $parts := tokenize($temp,"\.")
        let $combined := for $part in $parts return concat('tlg',$part)
        return string-join($combined,".")
    else 
    if ($a_type = 'stoa')
    then    
           replace($a_id,"-",".")
    else
    if ($a_type = 'abo')
    then 
        (: See bug 1159 :)
        let $parts := tokenize($a_id,"\.")
        return concat('phi',$parts[1],'.','abo',$parts[2])
    else 
        $a_id    
};




declare function frbr:make_cts($a_lang as xs:string,$a_id as xs:string,$a_mods as node()*,$a_ns as xs:string,$a_titles as xs:string) as node()
{        
    let $perseusInv := doc('/FRBR/perseuscts.xml')
    let $wordCounts := doc('/FRBR/wordcounts.xml')
    let $textgroup_id := concat($a_ns,":",substring-before($a_id,"."))
    let $work_id := concat($a_ns,":",substring-after($a_id,"."))
    let $perseusExpressions := $perseusInv//cts:textgroup[@projid=$textgroup_id]/cts:work[@projid=$work_id]/*[local-name(.) = 'edition' or local-name(.) = 'translation']
    return element cts:TextInventory {
        $perseusInv//cts:TextInventory/@*,
        $perseusInv//cts:TextInventory/node()[not(local-name() = 'textgroup')],
        element cts:textgroup {
            attribute projid {
                $textgroup_id
            },
            attribute urn {
                concat('urn:cts:',$textgroup_id)
            },
            element cts:groupname {
                attribute xml:lang { "en"},
                if ($perseusExpressions) 
                then $perseusExpressions[1]/ancestor::cts:textgroup/cts:groupname/text() 
                else 
                  string-join(for $creator in $a_mods[1]/mods:name[mods:role/mods:roleTerm = 'creator']
                  return replace($creator/mods:namePart[1],"\.$",""), " ")                    
            },            
            element cts:work {
                attribute projid {
                    $work_id
                },              
                attribute urn {
                    concat('urn:cts:',$a_ns,':',$a_id)
                },
                attribute xml:lang { $a_lang},
                element dc:title {
					attribute xml:lang { "en"},
                	if ($perseusExpressions)
                		then $perseusExpressions[1]/ancestor::cts:work/*:title/text()
                	else                 	                                      
                    	$a_titles[1]
                },
                (: add any perseus entries we have, inserting the cts urn :)
                (for $expression in $perseusExpressions
                    return 
                        if ($expression/@urn) then $expression 
                        else 
                            let $vtype := name($expression)
                            return 
                                element {$vtype} {
                                    attribute urn {
                                        concat('urn:cts:', $a_ns,':',$a_id,'.',substring-after($expression/@projid,':'))
                                    },
                                    $expression/@*,
                                    $expression/*
                                }
                ),
                
                    let $opplangs := distinct-values(($a_lang,$a_mods//mods:mods/mods:language[@objectPart = 'text' or not(@objectPart)]/mods:languageTerm))
                    let $all_opp := 
                        for $thislang in $opplangs
                            for $mods at $a_i in $a_mods
                                return
                                    if ($mods//mods:mods/mods:language[@objectPart = 'text' or not(@objectPart)]/mods:languageTerm = $thislang)
                                    then frbr:make_opp_version($a_id,$a_ns,$perseusExpressions,$a_lang,$a_titles,$mods,$a_i)
                                    else ()
                    return
                        (for $mods in $all_opp[@modsonly]
                        return $mods/*,
                        for $thislang in $opplangs 
                            for $mods at $a_i in $all_opp[*[contains(@projid,concat('opp-',$thislang))]]
                                let $renumbered :=
                                    existtx:transform($mods,doc('/db/xslt/fixoppver.xsl'),
                                        <parameters>
                                            <param name="e_base" value="{concat('urn:cts:',$a_ns,':',$a_id)}"/>
                                            <param name="e_lang" value="{$thislang}"/>
                                            <param name="e_ns" value="{$a_ns}"/>
                                            <param name="e_newVer" value="{$a_i}"/>
                                        </parameters>)
                               return $renumbered/*
                   )
                
            } (:end work:)        
        } (:end textgroup:)
    } (: end TextInventory:)
};

declare function frbr:make_opp_version($a_id,$a_ns,$a_perseusExpressions,$a_lang,$a_titles,$a_mods,$a_i)
{
    let $wordCounts := doc('/FRBR/wordcounts.xml')
    let $lang := ($a_mods/mods:language[@objectPart = 'text' or not(@objectPart)]/mods:languageTerm)[1]
    let $persLoc := $a_mods/mods:location/mods:url[starts-with(text(),"http://www.perseus.tufts.edu/hopper")]
    let $xId := concat($a_ns,':opp-',(if ($lang) then $lang else $a_lang),$a_i)
    let $projid :=
        if ($persLoc) then 
            let $persDoc := 
                (: handle subdocs :)
                let $full := substring-after($persLoc[1],"?doc=Perseus:text:")
                return if (contains($full,':')) then substring-before($full,':') else $full
            let $perseusId := 
                $a_perseusExpressions//cts:online[@docname = concat($persDoc,".xml")][1]/parent::*/@projid
            return if ($perseusId) then string($perseusId) else $xId                                 
        (: no perseus url id mods :)
        else $xId
    let $urn := concat('urn:cts:', $a_ns,':',$a_id,'.',substring-after($projid,':'))
    let $type :=
    if ($a_mods/mods:name[mods:role/mods:roleTerm = 'translator'] or 
        $a_mods/mods:subject[@authority='lcsh' and matches(mods:topic, "translation","i")] or
        $lang != $a_lang ) then "translation" else "edition"                                    
    return 
        element temp {
            (: only add new editions if we didn't have a perseus edition :)
            (if (not(contains($projid,$xId)))
            then
                attribute modsonly { 1 } 
            else 
                element  {concat ('cts:',$type) } {
                    if ($type = 'edition') 
                    then () 
                    else attribute xml:lang { if ($lang) then $lang else $a_lang },
                    attribute projid { $projid },
                    attribute urn { $urn },
                    (for $title in $a_mods/mods:titleInfo[@lang]/mods:title[not(. = $a_titles[1])]                                                                
                    return                                     
                        element cts:label {
                            attribute xml:lang { xs:string($title/@lang) },                                                                     
                            xs:string($title)
                        }
                    ),
                    (: Add the host titles :)
                    (for $title in ($a_mods/mods:relatedItem[@type='host']/mods:titleInfo[not(@type='alternative')])[1]/mods:title[not(. = $a_titles[1])]                                                                
                    return                                     
                        element cts:label {
                            attribute xml:lang { if ($title/@lang) then xs:string($title/@lang) else 'en' },                                                                     
                            xs:string($title)
                        }
                    ),
                    if ($a_mods/mods:titleInfo[not(@lang)]/mods:title[not(. = $a_titles[1])])
                    then
                        element cts:label {
                            attribute xml:lang { "en" },                                                                     
                            string-join($a_mods/mods:titleInfo/mods:title[not(@lang)],",")
                        }
                    else (),                                                                                                                
                    element cts:description{
                        attribute xml:lang { "en" },
                        string-join(
                            for $name in $a_mods/mods:name return 
                            string-join(($name/mods:namePart,$name/mods:role),",")
                            ," ")
                    }                                               
                } (:end edition/translation:)
            ),                       
            let $uniformTitle := 
                $a_mods/mods:titleInfo[mods:title = $a_titles[1]][1]
            let $wordCount := $wordCounts//count[@work=$a_id]
            return                                                    
                (: plugin the mods record, adding a cts identifier and word count if we have it:)                                             
                element mods:mods {
                    attribute xsi:schemaLocation { "http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-4.xsd" },
                    (: add the uniform title from the spreadsheet :)
                    if ($uniformTitle) then 
                        element mods:titleInfo {
                            $uniformTitle/@*[not(local-name(.) = 'type')],
                            if ($uniformTitle/@*[local-name(.) = 'lang']) then ()
                            else attribute xml:lang { 'en' },
                            attribute type { 'uniform' },
                            $uniformTitle/mods:title
                        }
                    else                                 
    	               element mods:titleInfo {
    	                   attribute xml:lang { 'en' },
    	                   attribute type { 'uniform' },
    	                   element mods:title { $a_titles[1] }
    	               },
    	            (: add the wordcount if we have it :)
    	            if ($wordCount) then 
                        element mods:part {
    	                   element mods:extent {
    	                       attribute unit { 'words' },
    	                       element mods:total { xs:int($wordCount) }
    	                   }
    	                }
    	            else (), (: no wordcount :)
    	            for $node in $a_mods/mods:titleInfo[not(@type='uniform') and not(mods:title = $a_titles[1])] return
    	               $node,
                    for $node in $a_mods/*[not(local-name(.) = 'titleInfo')]
                    return
                        if ( node-name($node) = QName("http://www.loc.gov/mods/v3","identifier") and
                                not(node-name($node/following-sibling::*[1]) = QName("http://www.loc.gov/mods/v3","identifier")) and
                                not ($node/preceding-sibling::mods:identifier[@type='ctsurn']) and 
                                not ($node/preceding-sibling::mods:identifier[@type='cts-urn']) and
                                not ($node/@type='cts-urn') and not($node/@type='ctsurn')
                                ) 
                        then 
                           ( frbr:normalize_display_label($node),
                            element mods:identifier {
                                attribute type {"ctsurn"},
                                concat("urn:cts:",$a_ns,":",$a_id,".",substring-after($projid,":"))                                                   
                            })
                            
                        (: make sure any existing urn is replaced with the correct version :)
                        else if (node-name($node) = QName("http://www.loc.gov/mods/v3","identifier") and 
                            ($node/@type='cts-urn' or $node/@type='ctsurn'))
                        then 
                            element mods:identifier {
                                attribute type {"ctsurn"},
                                concat("urn:cts:",$a_ns,":",$a_id,".",substring-after($projid,":"))                                                   
                            }
                        else if (node-name($node) = QName("http://www.loc.gov/mods/v3","identifier"))
                        then frbr:normalize_display_label($node)
                        else ($node)
                } (: end mods :)
                              
        } (: end temp wrapping element :)
};

declare function frbr:normalize_display_label($a_node as node()) as node() {
    let $origLabel := $a_node/@displayLabel
    let $newLabel := 
        if (matches($origLabel,'^(is)?commm?entaryon$','i'))
        then 'isCommentaryOn'
        else if (matches($origLabel,'^(is)?scholiato$','i'))
        then 'isScholiaTo' 
        else if (matches($origLabel,'^(is)?summaryof$','i'))
        then 'isSummaryOf' 
        else if (matches($origLabel,'^(is)?indexof$','i'))
        then 'isIndexOf'
        else if (matches($origLabel,'^(is)?epitomeof$','i'))
        then 'isEpitomeOf'
        else if (matches($origLabel,'^(is)?introductionto$','i'))
        then 'isIntroductionTo' 
        else if (matches($origLabel,'^(is)?paraphraseof$','i'))
        then 'isParaphraseOf'
        else if (matches($origLabel,'^(is)?quotedby$','i'))
        then 'isQuotedBy'
        else if (matches($origLabel, '^(is)?translationof\??$','i'))
        then 'isTranslationOf'
        else if (matches($origLabel,'^(is)?adaptationof','i'))
        then 'isAdaptationOf' 
        else if (matches($origLabel,'attributed','i'))
        then 'isAttributedTo'
        else $origLabel
    let $origText := $a_node/text()

return 
        element mods:identifier {
            if ($newLabel) then 
                attribute displayLabel {$newLabel}
            else (),
            $a_node/@*[not(local-name(.) = 'displayLabel')],
            $a_node/text()
        }    
};

declare function frbr:find_perseus($a_inv as node(), $a_ids as xs:string*,$a_types as xs:string*) as node()*
{        
    
    let $a_id :=  $a_ids[1]
    let $a_type := $a_types[1]
    let $ns := if (matches($a_type,'tlg')) then "greekLit" else "latinLit"    
    return
        (: if we don't have both an id and a type, just return :)
        if (not ($a_id) or not($a_type))
        then         
            ()       
        else
            let $textgroup_id := concat($ns,":", $a_type, substring-before($a_id,"."))
            let $work_id := concat($ns,":",$a_type, substring-after($a_id,"."))
            (: find any Perseus with this id as an identifier :)
            let $perseus := $a_inv//cts:textgroup[@projid=$textgroup_id]/cts:work[@projid=$work_id]/*
            return                
                if ($perseus)
                then
                    (<id>{$a_id}</id>,<type>{$a_type}</type>,())
                (: recurse for remaining ids if nothing found :)    
                else
                    frbr:find_perseus($a_inv,$a_ids[position() > 1], $a_types[position() > 1])
};

declare function frbr:find_mods($a_coll as node()*,$a_ids as xs:string*, $a_types as xs:string*,$a_lang as xs:string) 
{
    let $a_id :=  $a_ids[1]
    let $a_type := $a_types[1]
    let $check_type := if ($a_type = 'tlg_frag') then 'tlg' else $a_type
    let $alt_id := if (contains($a_id,'x')) then upper-case($a_id) else if (contains($a_id,'X')) then lower-case($a_id) else $a_id
    (: alternate version of id without leading 0 :)
    let $strip1 := replace($a_ids[1],"^0+","")
    let $stripped := if ($check_type = 'abo') then concat('Perseus:',$check_type,":phi,",replace($a_id,"\.",",")) else replace($strip1,"^([^\.]+\.)0+","$1")
    
    (: match on secondary sources :)
    let $secondSrcMatch := '^(is)?((commm?entaryon)|(scholiato)|(summaryof)|(indexof)|(epitomeof)|(introductionto)|(paraphraseof)|(quotedby))$'
    return
        (: if we don't have both an id and a type, just return :)
        if (not ($a_id) or not($a_type))
        then         
            ()       
        else
            (: find any mods records with this id as an identifier, and/or any consitituent records with this id as identifier :)        
            let $mods := $a_coll//mods:mods[mods:identifier[(not(@displayLabel) or not(matches(@displayLabel,$secondSrcMatch,'i'))) 
                            and contains(@type,$check_type) and (text() = $a_id or text() = $stripped or text() = $alt_id)]]                 
            let $constituent := $a_coll//mods:mods/descendant::mods:relatedItem[@type='constituent' and 
					                    mods:identifier[(not(@displayLabel) or not(matches(@displayLabel,$secondSrcMatch,'i'))) and
					                                    contains(@type,$check_type) and (text()= $a_id or text() = $stripped or text() = $alt_id)]]		
            let $related := $a_coll//mods:mods/descendant::mods:relatedItem[@type='constituent' and 
					                    mods:identifier[matches(@displayLabel,$secondSrcMatch,'i') and
					                                    contains(@type,$check_type) and (text() = $a_id or text() = $stripped or text() = $alt_id)]]		
            let $newmods :=       
                for $item in $constituent return
                    (: make a mods record from the consituent item :)
	               <mods 
	                   xmlns="http://www.loc.gov/mods/v3" 
	                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
	                   xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
	                   {($item/*, frbr:reverse_related($item))}
	               </mods>
	         let $newrel :=       
                for $item in $related return
                    (: make a mods record from the related item :)
	               <mods 
	                   xmlns="http://www.loc.gov/mods/v3" 
	                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
	                   xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
	                   {$item/*}                    	 	    
	                   <relatedItem type="host" xmlns="http://www.loc.gov/mods/v3">
	                       {$item/parent::mods:mods/*[local-name(.) != 'relatedItem']}
	                   </relatedItem>
	               </mods>
	       return
	           if ($mods or $newmods)
	           then 
	               let $all_mods := 
	                   for $item in ($mods,$newmods)
	                       (: gather the languages for the text in this MODS record ... sometimes we have @objectPart specified and sometimes not:)
	                       let $languages := distinct-values($item/mods:language[@objectPart = 'text' or not(@objectPart)]/mods:languageTerm) 
	                       return
	                           (:split mods files that combine facing translations in a single record :)
	                           (: but exclude the Perseus ones which are already split :)
	                           if (count($languages) > 0 and count($item/mods:identifier[matches(.,'^Perseus:text:.*')]) != 1)
	                           then
	                               for $lang in $languages return
	                                     <mods 
	                                       xmlns="http://www.loc.gov/mods/v3" 
	                                       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
	                                       xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
	                                       {
	                                           $item/*[not(local-name(.) = 'language') and not(local-name(.) = 'name') and not(local-name(.) = 'subject')],
	                                           $item/mods:language[mods:languageTerm[text() = $lang]],
	                                           (: eliminate translator role, translation subject for source language only :)
	                                           (for $name in $item/mods:name return
	                                               if ($name/mods:role/mods:roleTerm = 'translator' and $lang = $a_lang) then
	                                                   <mods:name>{
	                                                       $name/@*,
	                                                       $name/mods:role[mods:roleTerm != 'translator']
	                                                   }</mods:name> 
	                                               else $name
	                                           ), 
	                                           (for $subject in $item/mods:subject return
	                                               if ($subject/@authority='lcsh' and matches($subject/mods:topic,"translation","i") and $lang = $a_lang) then () else $subject)
	                                        }
	                                     </mods>
	                          else 
	                               $item
	               return <found><id>{$a_id}</id>,<type>{$a_type}</type>,<expressions>{$all_mods}</expressions><related>{$newrel}</related></found>
			   else (: recurse for remaining ids if nothing found :)
                    frbr:find_mods($a_coll,$a_ids[position() > 1], $a_types[position() > 1],$a_lang)
};

declare function frbr:reverse_related($a_node as node()) as node() {
        if ( $a_node/parent::mods:relatedItem )
        then 
        <relatedItem type="host" xmlns="http://www.loc.gov/mods/v3">
                {(
                    $a_node/parent::mods:relatedItem/@*[local-name(.) != 'type'],
                    $a_node/parent::mods:relatedItem/*[local-name(.) != 'relatedItem'],
                    frbr:reverse_related($a_node/parent::mods:relatedItem)
                )}
	       </relatedItem>
        else 
           <relatedItem type="host" xmlns="http://www.loc.gov/mods/v3">
                {$a_node/parent::mods:mods/*[local-name(.) != 'relatedItem']}
	       </relatedItem>
};