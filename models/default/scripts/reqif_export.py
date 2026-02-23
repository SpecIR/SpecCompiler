#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
import sqlite3
import sys
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple


def _now_reqif_timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="milliseconds")


def _stable_id(prefix: str, value: str) -> str:
    h = hashlib.sha1(value.encode("utf-8")).hexdigest()
    return f"_{prefix}-{h}"


def _repo_root_from_this_file() -> str:
    # models/default/scripts/reqif_export.py -> up 4 -> <repo_root> (where ./reqif lives)
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))


def _ensure_reqif_on_path() -> None:
    try:
        import reqif  # noqa: F401
        return
    except ModuleNotFoundError:
        pass

    repo_root = _repo_root_from_this_file()
    candidate = os.path.join(repo_root, "reqif")
    if os.path.isdir(candidate):
        sys.path.insert(0, candidate)
        return

    raise SystemExit(
        "error: cannot import 'reqif'. Install it (pip) or ensure ./reqif exists next to speccompiler-core."
    )


@dataclass(frozen=True)
class SpecObjectRow:
    id: str
    type_ref: str
    pid: Optional[str]
    title_text: Optional[str]
    level: int
    file_seq: int
    content_xhtml: Optional[str]


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def _get_spec_ids(conn: sqlite3.Connection) -> List[str]:
    rows = conn.execute("SELECT identifier FROM specifications ORDER BY identifier").fetchall()
    return [str(r["identifier"]) for r in rows]


def _get_spec_title(conn: sqlite3.Connection, spec_id: str) -> str:
    row = conn.execute(
        "SELECT long_name, pid, root_path FROM specifications WHERE identifier = ?",
        (spec_id,),
    ).fetchone()
    if not row:
        return spec_id
    if row["long_name"]:
        return str(row["long_name"])
    if row["pid"]:
        return str(row["pid"])
    if row["root_path"]:
        return os.path.basename(str(row["root_path"]))
    return spec_id


def _load_spec_objects(conn: sqlite3.Connection, spec_id: str) -> List[SpecObjectRow]:
    rows = conn.execute(
        """
        SELECT id, type_ref, pid, title_text, level, file_seq, content_xhtml
        FROM spec_objects
        WHERE specification_ref = ?
        ORDER BY file_seq ASC
        """,
        (spec_id,),
    ).fetchall()

    out: List[SpecObjectRow] = []
    for r in rows:
        out.append(
            SpecObjectRow(
                id=str(r["id"]),
                type_ref=str(r["type_ref"]),
                pid=str(r["pid"]) if r["pid"] is not None else None,
                title_text=str(r["title_text"]) if r["title_text"] is not None else None,
                level=int(r["level"]) if r["level"] is not None else 2,
                file_seq=int(r["file_seq"]),
                content_xhtml=str(r["content_xhtml"]) if r["content_xhtml"] is not None else None,
            )
        )
    return out


def _build_hierarchy(objects: List[SpecObjectRow]) -> List[Tuple[SpecObjectRow, List]]:
    root: List[Tuple[SpecObjectRow, List]] = []
    stack: List[Tuple[int, List[Tuple[SpecObjectRow, List]]]] = [(0, root)]

    for row in objects:
        hier_level = max(1, int(row.level) - 1)
        while stack and hier_level <= stack[-1][0]:
            stack.pop()
        parent_children = stack[-1][1] if stack else root
        node: Tuple[SpecObjectRow, List] = (row, [])
        parent_children.append(node)
        stack.append((hier_level, node[1]))
    return root


def _load_datatype_definitions(conn: sqlite3.Connection) -> Dict[str, str]:
    rows = conn.execute("SELECT identifier, type FROM datatype_definitions").fetchall()
    return {str(r["identifier"]): str(r["type"]) for r in rows}


def _load_enum_values(conn: sqlite3.Connection) -> Dict[str, List[Tuple[str, str]]]:
    rows = conn.execute(
        "SELECT datatype_ref, identifier, key FROM enum_values ORDER BY datatype_ref, sequence"
    ).fetchall()
    out: Dict[str, List[Tuple[str, str]]] = {}
    for r in rows:
        dt_ref = str(r["datatype_ref"])
        out.setdefault(dt_ref, []).append((str(r["identifier"]), str(r["key"])))
    return out


def _load_object_types(conn: sqlite3.Connection) -> Dict[str, Dict[str, Any]]:
    rows = conn.execute(
        "SELECT identifier, long_name, description FROM spec_object_types ORDER BY identifier"
    ).fetchall()
    out: Dict[str, Dict[str, Any]] = {}
    for r in rows:
        out[str(r["identifier"])] = {
            "id": str(r["identifier"]),
            "long_name": str(r["long_name"]) if r["long_name"] is not None else str(r["identifier"]),
            "description": str(r["description"]) if r["description"] is not None else None,
        }
    return out


def _load_attribute_types(conn: sqlite3.Connection) -> List[sqlite3.Row]:
    return conn.execute(
        """
        SELECT owner_type_ref, long_name, datatype_ref
        FROM spec_attribute_types
        ORDER BY owner_type_ref, long_name
        """
    ).fetchall()


def _load_attribute_values(conn: sqlite3.Connection, spec_id: str) -> Dict[str, List[sqlite3.Row]]:
    rows = conn.execute(
        """
        SELECT
          av.owner_object_id,
          av.name,
          av.raw_value,
          av.string_value,
          av.int_value,
          av.real_value,
          av.bool_value,
          av.date_value,
          av.enum_ref,
          av.datatype,
          av.xhtml_value,
          ev.key AS enum_key
        FROM spec_attribute_values av
        LEFT JOIN enum_values ev ON ev.identifier = av.enum_ref
        WHERE av.specification_ref = ?
        ORDER BY av.owner_object_id, av.name
        """,
        (spec_id,),
    ).fetchall()

    out: Dict[str, List[sqlite3.Row]] = {}
    for r in rows:
        out.setdefault(str(r["owner_object_id"]), []).append(r)
    return out


def _load_relations(conn: sqlite3.Connection, spec_id: str) -> List[sqlite3.Row]:
    return conn.execute(
        """
        SELECT r.id, r.type_ref, r.source_object_id, r.target_object_id
        FROM spec_relations r
        JOIN spec_objects s1 ON s1.id = r.source_object_id
        JOIN spec_objects s2 ON s2.id = r.target_object_id
        WHERE r.specification_ref = ?
          AND r.target_object_id IS NOT NULL
        ORDER BY r.id
        """,
        (spec_id,),
    ).fetchall()


def _load_relation_types(conn: sqlite3.Connection) -> Dict[str, Dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT identifier, long_name, description
        FROM spec_relation_types
        ORDER BY identifier
        """
    ).fetchall()
    out: Dict[str, Dict[str, Any]] = {}
    for r in rows:
        out[str(r["identifier"])] = {
            "id": str(r["identifier"]),
            "long_name": str(r["long_name"]) if r["long_name"] is not None else str(r["identifier"]),
            "description": str(r["description"]) if r["description"] is not None else None,
        }
    return out


def _pick_default_relation_type(relation_types: Dict[str, Dict[str, Any]]) -> Optional[str]:
    # Use first relation type in sorted order as the default.
    if relation_types:
        return sorted(relation_types.keys())[0]
    return None


def build_reqif_bundle(conn: sqlite3.Connection, spec_id: str):
    _ensure_reqif_on_path()

    from reqif.helpers.lxml import lxml_convert_to_reqif_ns_xhtml_string
    from reqif.models.reqif_core_content import ReqIFCoreContent
    from reqif.models.reqif_data_type import (
        ReqIFDataTypeDefinitionBoolean,
        ReqIFDataTypeDefinitionDateIdentifier,
        ReqIFDataTypeDefinitionEnumeration,
        ReqIFDataTypeDefinitionInteger,
        ReqIFDataTypeDefinitionReal,
        ReqIFDataTypeDefinitionString,
        ReqIFDataTypeDefinitionXHTML,
        ReqIFEnumValue,
    )
    from reqif.models.reqif_namespace_info import ReqIFNamespaceInfo
    from reqif.models.reqif_req_if_content import ReqIFReqIFContent
    from reqif.models.reqif_reqif_header import ReqIFReqIFHeader
    from reqif.models.reqif_spec_hierarchy import ReqIFSpecHierarchy
    from reqif.models.reqif_spec_object import ReqIFSpecObject, SpecObjectAttribute
    from reqif.models.reqif_spec_object_type import ReqIFSpecObjectType, SpecAttributeDefinition
    from reqif.models.reqif_spec_relation import ReqIFSpecRelation
    from reqif.models.reqif_spec_relation_type import ReqIFSpecRelationType
    from reqif.models.reqif_specification import ReqIFSpecification
    from reqif.models.reqif_specification_type import ReqIFSpecificationType
    from reqif.models.reqif_types import SpecObjectAttributeType
    from reqif.object_lookup import ReqIFObjectLookup
    from reqif.reqif_bundle import ReqIFBundle

    now = _now_reqif_timestamp()
    spec_title = _get_spec_title(conn, spec_id)

    datatype_types = _load_datatype_definitions(conn)
    enum_values_by_dt = _load_enum_values(conn)

    def make_datatype(dt_id: str, primitive: str):
        reqif_id = _stable_id("DT", dt_id)
        if primitive == "STRING":
            return ReqIFDataTypeDefinitionString(identifier=reqif_id, long_name=dt_id, last_change=now)
        if primitive == "INTEGER":
            return ReqIFDataTypeDefinitionInteger(identifier=reqif_id, long_name=dt_id, last_change=now)
        if primitive == "REAL":
            return ReqIFDataTypeDefinitionReal(identifier=reqif_id, long_name=dt_id, last_change=now)
        if primitive == "BOOLEAN":
            return ReqIFDataTypeDefinitionBoolean(identifier=reqif_id, long_name=dt_id, last_change=now)
        if primitive == "DATE":
            return ReqIFDataTypeDefinitionDateIdentifier(identifier=reqif_id, long_name=dt_id, last_change=now)
        if primitive == "XHTML":
            return ReqIFDataTypeDefinitionXHTML(identifier=reqif_id, long_name=dt_id, last_change=now)
        if primitive == "ENUM":
            enum_rows = enum_values_by_dt.get(dt_id, [])
            values: List[ReqIFEnumValue] = []
            for enum_identifier, enum_key in enum_rows:
                values.append(ReqIFEnumValue.create(identifier=_stable_id("EV", enum_identifier), key=enum_key))
            return ReqIFDataTypeDefinitionEnumeration(identifier=reqif_id, long_name=dt_id, last_change=now, values=values)
        # Fallback to string.
        return ReqIFDataTypeDefinitionString(identifier=reqif_id, long_name=dt_id, last_change=now)

    reqif_datatypes: Dict[str, Any] = {}
    for dt_id, primitive in sorted(datatype_types.items()):
        reqif_datatypes[dt_id] = make_datatype(dt_id, primitive)

    # Ensure core datatypes exist even if DB is minimal.
    if "STRING" not in reqif_datatypes:
        reqif_datatypes["STRING"] = make_datatype("STRING", "STRING")
    if "XHTML" not in reqif_datatypes:
        reqif_datatypes["XHTML"] = make_datatype("XHTML", "XHTML")

    core_defs = {
        "foreign_id": SpecAttributeDefinition.create(
            attribute_type=SpecObjectAttributeType.STRING,
            identifier=_stable_id("AD", "ReqIF.ForeignID"),
            datatype_definition=reqif_datatypes["STRING"].identifier,
            long_name="ReqIF.ForeignID",
        ),
        "name": SpecAttributeDefinition.create(
            attribute_type=SpecObjectAttributeType.STRING,
            identifier=_stable_id("AD", "ReqIF.Name"),
            datatype_definition=reqif_datatypes["STRING"].identifier,
            long_name="ReqIF.Name",
        ),
        "text": SpecAttributeDefinition.create(
            attribute_type=SpecObjectAttributeType.XHTML,
            identifier=_stable_id("AD", "ReqIF.Text"),
            datatype_definition=reqif_datatypes["XHTML"].identifier,
            long_name="ReqIF.Text",
        ),
    }

    object_types = _load_object_types(conn)
    attribute_types_rows = _load_attribute_types(conn)
    attr_values_by_owner = _load_attribute_values(conn, spec_id)

    # Build attribute definition map per (owner_type, attr_name) -> SpecAttributeDefinition.
    reqif_attr_defs_by_owner: Dict[str, Dict[str, SpecAttributeDefinition]] = {}
    for row in attribute_types_rows:
        owner = str(row["owner_type_ref"])
        name = str(row["long_name"])
        datatype_ref = str(row["datatype_ref"])
        primitive = datatype_types.get(datatype_ref, "STRING")

        if name in ("ReqIF.ForeignID", "ReqIF.Name", "ReqIF.Text"):
            continue

        if primitive == "ENUM":
            attribute_type = SpecObjectAttributeType.ENUMERATION
        elif primitive == "INTEGER":
            attribute_type = SpecObjectAttributeType.INTEGER
        elif primitive == "REAL":
            attribute_type = SpecObjectAttributeType.REAL
        elif primitive == "BOOLEAN":
            attribute_type = SpecObjectAttributeType.BOOLEAN
        elif primitive == "DATE":
            attribute_type = SpecObjectAttributeType.DATE
        elif primitive == "XHTML":
            attribute_type = SpecObjectAttributeType.XHTML
        else:
            attribute_type = SpecObjectAttributeType.STRING

        reqif_def = SpecAttributeDefinition.create(
            attribute_type=attribute_type,
            identifier=_stable_id("AD", f"{owner}:{name}"),
            datatype_definition=reqif_datatypes.get(datatype_ref, reqif_datatypes["STRING"]).identifier,
            long_name=name,
        )
        reqif_attr_defs_by_owner.setdefault(owner, {})[name] = reqif_def

    # Build ReqIF SpecObjectTypes.
    reqif_spec_object_types: Dict[str, ReqIFSpecObjectType] = {}
    for type_id, info in object_types.items():
        defs = [core_defs["foreign_id"], core_defs["name"], core_defs["text"]]
        defs.extend(list(reqif_attr_defs_by_owner.get(type_id, {}).values()))
        reqif_spec_object_types[type_id] = ReqIFSpecObjectType.create(
            identifier=_stable_id("SOT", type_id),
            long_name=info.get("long_name") or type_id,
            description=info.get("description"),
            last_change=now,
            attribute_definitions=defs,
        )

    # SpecObjects and hierarchy.
    objects = _load_spec_objects(conn, spec_id)
    reqif_objects: List[ReqIFSpecObject] = []
    reqif_object_id_by_sd_id: Dict[str, str] = {}

    # Map SpecCompiler enum_value identifier -> ReqIF enum value identifier.
    reqif_enum_id_by_sd_enum_id: Dict[str, str] = {}
    for dt_id, enum_rows in enum_values_by_dt.items():
        for enum_identifier, _enum_key in enum_rows:
            reqif_enum_id_by_sd_enum_id[enum_identifier] = _stable_id("EV", enum_identifier)

    for row in objects:
        reqif_obj_id = _stable_id("SO", row.id)
        reqif_object_id_by_sd_id[row.id] = reqif_obj_id

        values: List[SpecObjectAttribute] = []
        pid = row.pid or row.id
        title = row.title_text or row.pid or row.id

        values.append(
            SpecObjectAttribute(
                attribute_type=SpecObjectAttributeType.STRING,
                definition_ref=core_defs["foreign_id"].identifier,
                value=str(pid),
            )
        )
        values.append(
            SpecObjectAttribute(
                attribute_type=SpecObjectAttributeType.STRING,
                definition_ref=core_defs["name"].identifier,
                value=str(title),
            )
        )

        html_fragment = (row.content_xhtml or "").strip()
        if not html_fragment:
            html_fragment = "<div></div>"
        else:
            html_fragment = f"<div>{html_fragment}</div>"
        xhtml_value = lxml_convert_to_reqif_ns_xhtml_string(html_fragment, reqif_xhtml=False)
        values.append(
            SpecObjectAttribute(
                attribute_type=SpecObjectAttributeType.XHTML,
                definition_ref=core_defs["text"].identifier,
                value=xhtml_value,
                value_stripped_xhtml=None,
            )
        )

        # Map SpecCompiler EAV attributes.
        owner_attrs = attr_values_by_owner.get(row.id, [])
        defs_for_type = reqif_attr_defs_by_owner.get(row.type_ref, {})
        for av in owner_attrs:
            name = str(av["name"])
            if name in ("ReqIF.ForeignID", "ReqIF.Name", "ReqIF.Text"):
                continue
            if name not in defs_for_type:
                continue

            reqif_def = defs_for_type[name]
            primitive = str(av["datatype"]) if av["datatype"] is not None else "STRING"

            if primitive == "ENUM":
                if av["enum_ref"] is None:
                    continue
                enum_ref = str(av["enum_ref"])
                reqif_enum_id = reqif_enum_id_by_sd_enum_id.get(enum_ref)
                if not reqif_enum_id:
                    continue
                values.append(
                    SpecObjectAttribute(
                        attribute_type=SpecObjectAttributeType.ENUMERATION,
                        definition_ref=reqif_def.identifier,
                        value=[reqif_enum_id],
                    )
                )
            elif primitive == "XHTML":
                frag = (str(av["xhtml_value"]) if av["xhtml_value"] is not None else "").strip()
                if not frag:
                    continue
                frag_wrapped = f"<div>{frag}</div>"
                xhtml_attr_value = lxml_convert_to_reqif_ns_xhtml_string(frag_wrapped, reqif_xhtml=False)
                values.append(
                    SpecObjectAttribute(
                        attribute_type=SpecObjectAttributeType.XHTML,
                        definition_ref=reqif_def.identifier,
                        value=xhtml_attr_value,
                        value_stripped_xhtml=None,
                    )
                )
            else:
                val = None
                if av["string_value"] is not None:
                    val = str(av["string_value"])
                elif av["int_value"] is not None:
                    val = str(av["int_value"])
                elif av["real_value"] is not None:
                    val = str(av["real_value"])
                elif av["bool_value"] is not None:
                    val = "true" if int(av["bool_value"]) == 1 else "false"
                elif av["date_value"] is not None:
                    val = str(av["date_value"])
                elif av["raw_value"] is not None:
                    val = str(av["raw_value"])
                if val is None:
                    continue
                values.append(
                    SpecObjectAttribute(
                        attribute_type=SpecObjectAttributeType.STRING,
                        definition_ref=reqif_def.identifier,
                        value=val,
                    )
                )

        reqif_obj_type = reqif_spec_object_types.get(row.type_ref) or reqif_spec_object_types.get("SECTION")
        assert reqif_obj_type is not None

        reqif_objects.append(
            ReqIFSpecObject(
                identifier=reqif_obj_id,
                attributes=values,
                spec_object_type=reqif_obj_type.identifier,
                long_name=title,
                last_change=now,
            )
        )

    hierarchy_tree = _build_hierarchy(objects)

    def make_hierarchy_nodes(nodes: List[Tuple[SpecObjectRow, List]]) -> List[ReqIFSpecHierarchy]:
        out_nodes: List[ReqIFSpecHierarchy] = []
        for sd_row, children in nodes:
            sd_level = sd_row.level or 2
            hier_level = max(1, int(sd_level) - 1)
            out_nodes.append(
                ReqIFSpecHierarchy(
                    xml_node=None,
                    is_self_closed=False,
                    identifier=_stable_id("H", f"{spec_id}:{sd_row.id}"),
                    last_change=now,
                    long_name=None,
                    spec_object=reqif_object_id_by_sd_id[sd_row.id],
                    children=make_hierarchy_nodes(children),
                    ref_then_children_order=True,
                    level=hier_level,
                )
            )
        return out_nodes

    specification_type = ReqIFSpecificationType(
        identifier=_stable_id("ST", "SpecCompiler.SpecificationType"),
        last_change=now,
        long_name="SpecCompiler Specification",
        spec_attributes=None,
        spec_attribute_map={},
        is_self_closed=True,
    )

    specification = ReqIFSpecification(
        identifier=_stable_id("S", spec_id),
        last_change=now,
        long_name=spec_title,
        values=[],
        specification_type=specification_type.identifier,
        children=make_hierarchy_nodes(hierarchy_tree),
    )

    # Relation types + relations.
    relation_types = _load_relation_types(conn)
    default_rel = _pick_default_relation_type(relation_types)

    reqif_relation_types: Dict[str, ReqIFSpecRelationType] = {}
    for rel_id, rel in relation_types.items():
        reqif_relation_types[rel_id] = ReqIFSpecRelationType(
            identifier=_stable_id("SRT", rel_id),
            description=rel.get("description"),
            last_change=now,
            long_name=rel.get("long_name") or rel_id,
            is_self_closed=True,
            attribute_definitions=None,
        )

    reqif_relations: List[ReqIFSpecRelation] = []
    for rel in _load_relations(conn, spec_id):
        type_ref = str(rel["type_ref"]) if rel["type_ref"] is not None else default_rel
        if not type_ref or type_ref not in reqif_relation_types:
            continue
        src = str(rel["source_object_id"])
        tgt = str(rel["target_object_id"])
        if src not in reqif_object_id_by_sd_id or tgt not in reqif_object_id_by_sd_id:
            continue
        reqif_relations.append(
            ReqIFSpecRelation(
                identifier=_stable_id("SR", str(rel["id"])),
                relation_type_ref=reqif_relation_types[type_ref].identifier,
                source=reqif_object_id_by_sd_id[src],
                target=reqif_object_id_by_sd_id[tgt],
                last_change=now,
                long_name=None,
            )
        )

    reqif_content = ReqIFReqIFContent(
        data_types=list(reqif_datatypes.values()),
        spec_types=[
            specification_type,
            *reqif_spec_object_types.values(),
            *reqif_relation_types.values(),
        ],
        spec_objects=reqif_objects,
        spec_relations=reqif_relations,
        specifications=[specification],
        spec_relation_groups=[],
    )

    bundle = ReqIFBundle(
        namespace_info=ReqIFNamespaceInfo.create_default(),
        req_if_header=ReqIFReqIFHeader(
            identifier=_stable_id("HDR", spec_id),
            creation_time=now,
            repository_id="speccompiler",
            req_if_tool_id="speccompiler",
            req_if_version="1.0",
            source_tool_id="speccompiler",
            title=f"SpecCompiler export: {spec_title}",
        ),
        core_content=ReqIFCoreContent(req_if_content=reqif_content),
        tool_extensions_tag_exists=False,
        lookup=ReqIFObjectLookup.empty(),
        exceptions=[],
    )

    return bundle


def main() -> int:
    parser = argparse.ArgumentParser(description="Export SpecCompiler specir.db to ReqIF (model-level exporter).")
    parser.add_argument("--db", required=True, help="Path to specir.db")
    parser.add_argument("--output", required=True, help="Output .reqif path")
    parser.add_argument("--spec-id", default=None, help="Specification identifier to export")
    args = parser.parse_args()

    db_path = os.path.abspath(args.db)
    out_path = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    with _connect(db_path) as conn:
        spec_ids = _get_spec_ids(conn)
        if not spec_ids:
            print("error: no specifications found in DB.", file=sys.stderr)
            return 2

        spec_id = args.spec_id
        if spec_id is None:
            if len(spec_ids) != 1:
                print(f"error: DB has multiple specifications: {spec_ids}. Provide --spec-id.", file=sys.stderr)
                return 2
            spec_id = spec_ids[0]
        if spec_id not in spec_ids:
            print(f"error: spec-id not found: {spec_id}", file=sys.stderr)
            return 2

        bundle = build_reqif_bundle(conn, spec_id)

    _ensure_reqif_on_path()
    from reqif.unparser import ReqIFUnparser

    xml = ReqIFUnparser.unparse(bundle)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml)

    print(f"Wrote ReqIF: {out_path}")
    print(f"SpecCompiler spec_id: {spec_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

