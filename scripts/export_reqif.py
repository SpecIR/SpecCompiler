#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import os
import sqlite3
import sys
import uuid
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Tuple


def _repo_root_from_this_file() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _now_reqif_timestamp() -> str:
    # ReqIF examples commonly use ISO8601 with offset and milliseconds.
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="milliseconds")


def _reqif_id(prefix: str) -> str:
    # ReqIF schema validation expects IDENTIFIER values to be valid XML ID/NCName-like.
    # Ensure leading underscore to avoid starting with a digit.
    return f"_{prefix}-{uuid.uuid4().hex}"


def _sanitize_attr_id(name: str) -> str:
    # Stable-ish identifier component (still prefixed with underscore elsewhere).
    out = []
    for ch in name.strip():
        if ch.isalnum() or ch in ("_", "-", "."):
            out.append(ch)
        else:
            out.append("_")
    s = "".join(out).strip("_")
    return s if s else "attr"


def _pandoc_json_to_text(node: Any) -> str:
    # Minimal Pandoc JSON -> plain text conversion good enough for prototype.
    # Handles common block/inline types produced by SpecCompiler.
    if node is None:
        return ""

    if isinstance(node, str):
        return node

    if isinstance(node, (int, float, bool)):
        return str(node)

    if isinstance(node, list):
        parts = [_pandoc_json_to_text(x) for x in node]
        return "".join(parts)

    if isinstance(node, dict):
        t = node.get("t")
        c = node.get("c")

        if t == "Str":
            return str(c or "")
        if t == "Space":
            return " "
        if t in ("SoftBreak", "LineBreak"):
            return "\n"
        if t == "Code":
            # c = [attr, text]
            if isinstance(c, list) and len(c) == 2:
                return str(c[1])
            return ""
        if t in ("Emph", "Strong", "Span", "Underline", "Strikeout", "SmallCaps", "Superscript", "Subscript"):
            return _pandoc_json_to_text(c)
        if t == "Link":
            # c = [attr, inlines, target]
            if isinstance(c, list) and len(c) >= 2:
                return _pandoc_json_to_text(c[1])
            return ""
        if t == "Image":
            # c = [attr, alt, target]
            if isinstance(c, list) and len(c) >= 2:
                return _pandoc_json_to_text(c[1])
            return ""
        if t in ("Para", "Plain"):
            return _pandoc_json_to_text(c) + "\n"
        if t == "Header":
            # c = [level, attr, inlines]
            if isinstance(c, list) and len(c) == 3:
                return _pandoc_json_to_text(c[2]) + "\n"
            return ""
        if t == "BlockQuote":
            return _pandoc_json_to_text(c) + "\n"
        if t == "BulletList":
            # c = list of items, each item is list of blocks
            if isinstance(c, list):
                lines = []
                for item in c:
                    item_text = _pandoc_json_to_text(item).strip()
                    if item_text:
                        lines.append(f"- {item_text}")
                return "\n".join(lines) + "\n"
            return ""
        if t == "OrderedList":
            # c = [attrs, items]
            if isinstance(c, list) and len(c) == 2 and isinstance(c[1], list):
                lines = []
                for i, item in enumerate(c[1], start=1):
                    item_text = _pandoc_json_to_text(item).strip()
                    if item_text:
                        lines.append(f"{i}. {item_text}")
                return "\n".join(lines) + "\n"
            return ""
        if t == "CodeBlock":
            # c = [attr, text]
            if isinstance(c, list) and len(c) == 2:
                return str(c[1]) + "\n"
            return ""
        if t == "Div":
            # c = [attr, blocks]
            if isinstance(c, list) and len(c) == 2:
                return _pandoc_json_to_text(c[1]) + "\n"
            return ""

        # Fallback: try to stringify children.
        return _pandoc_json_to_text(c)

    return ""


def _text_to_xhtml_div(text: str) -> str:
    # Produce a simple XHTML fragment wrapped in a <div>.
    escaped = html.escape(text or "")
    escaped = escaped.replace("\r\n", "\n").replace("\r", "\n")
    escaped = escaped.replace("\n", "<br/>")
    return f"<div>{escaped}</div>"


@dataclass(frozen=True)
class SpecObjectRow:
    identifier: str
    type_ref: str
    pid: Optional[str]
    title_text: Optional[str]
    level: Optional[int]
    file_seq: int
    ast: Optional[str]


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def _get_spec_ids(conn: sqlite3.Connection) -> List[str]:
    rows = conn.execute("SELECT identifier FROM specifications ORDER BY identifier").fetchall()
    return [str(r["identifier"]) for r in rows]


def _load_spec_title(conn: sqlite3.Connection, spec_id: str) -> str:
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
        SELECT identifier, type_ref, pid, title_text, level, file_seq, ast
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
                identifier=str(r["identifier"]),
                type_ref=str(r["type_ref"]),
                pid=str(r["pid"]) if r["pid"] is not None else None,
                title_text=str(r["title_text"]) if r["title_text"] is not None else None,
                level=int(r["level"]) if r["level"] is not None else None,
                file_seq=int(r["file_seq"]),
                ast=str(r["ast"]) if r["ast"] is not None else None,
            )
        )
    return out


def _load_all_attributes_for_spec(
    conn: sqlite3.Connection, spec_id: str
) -> Tuple[Dict[str, Dict[str, str]], List[str]]:
    rows = conn.execute(
        """
        SELECT
          av.owner_ref,
          av.name,
          av.raw_value,
          av.string_value,
          av.int_value,
          av.real_value,
          av.bool_value,
          av.date_value,
          av.datatype,
          ev.key AS enum_key
        FROM spec_attribute_values av
        LEFT JOIN enum_values ev ON ev.identifier = av.enum_ref
        WHERE av.specification_ref = ?
        ORDER BY av.owner_ref ASC, av.name ASC
        """,
        (spec_id,),
    ).fetchall()

    by_owner: Dict[str, Dict[str, str]] = {}
    names: List[str] = []
    seen: set[str] = set()

    for r in rows:
        owner_ref = str(r["owner_ref"])
        name = str(r["name"])
        dtype = str(r["datatype"]) if r["datatype"] is not None else "STRING"

        value: Optional[str] = None
        if dtype == "ENUM" and r["enum_key"] is not None:
            value = str(r["enum_key"])
        elif r["string_value"] is not None:
            value = str(r["string_value"])
        elif r["int_value"] is not None:
            value = str(r["int_value"])
        elif r["real_value"] is not None:
            value = str(r["real_value"])
        elif r["bool_value"] is not None:
            value = "true" if int(r["bool_value"]) == 1 else "false"
        elif r["date_value"] is not None:
            value = str(r["date_value"])
        elif r["raw_value"] is not None:
            value = str(r["raw_value"])

        if value is None:
            continue

        if owner_ref not in by_owner:
            by_owner[owner_ref] = {}
        by_owner[owner_ref][name] = value

        if name not in seen:
            seen.add(name)
            names.append(name)

    names.sort()
    return by_owner, names


def _build_spec_hierarchy(objects: List[SpecObjectRow]) -> List[Tuple[SpecObjectRow, List]]:
    # Returns a nested structure: [(row, children), ...]
    root: List[Tuple[SpecObjectRow, List]] = []
    stack: List[Tuple[int, List[Tuple[SpecObjectRow, List]]]] = [(0, root)]  # (hier_level, children_list)

    for row in objects:
        raw_level = row.level or 2
        hier_level = max(1, int(raw_level) - 1)  # H2 -> 1

        while stack and hier_level <= stack[-1][0]:
            stack.pop()

        parent_children = stack[-1][1] if stack else root
        node: Tuple[SpecObjectRow, List] = (row, [])
        parent_children.append(node)
        stack.append((hier_level, node[1]))

    return root


def main() -> int:
    parser = argparse.ArgumentParser(description="Prototype: export SpecCompiler SpecIR SQLite DB to ReqIF.")
    parser.add_argument("--db", required=True, help="Path to specir.db (SQLite)")
    parser.add_argument("--out", required=True, help="Output .reqif file path")
    parser.add_argument("--spec-id", default=None, help="SpecCompiler specification identifier to export")
    args = parser.parse_args()

    db_path = os.path.abspath(args.db)
    out_path = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    repo_root = _repo_root_from_this_file()
    reqif_root = os.path.join(repo_root, "reqif")
    if not os.path.isdir(reqif_root):
        print(f"error: reqif library not found at: {reqif_root}", file=sys.stderr)
        return 2
    sys.path.insert(0, reqif_root)

    from reqif.helpers.lxml import lxml_convert_to_reqif_ns_xhtml_string  # type: ignore
    from reqif.models.reqif_core_content import ReqIFCoreContent  # type: ignore
    from reqif.models.reqif_data_type import (  # type: ignore
        ReqIFDataTypeDefinitionString,
        ReqIFDataTypeDefinitionXHTML,
    )
    from reqif.models.reqif_namespace_info import ReqIFNamespaceInfo  # type: ignore
    from reqif.models.reqif_req_if_content import ReqIFReqIFContent  # type: ignore
    from reqif.models.reqif_reqif_header import ReqIFReqIFHeader  # type: ignore
    from reqif.models.reqif_spec_hierarchy import ReqIFSpecHierarchy  # type: ignore
    from reqif.models.reqif_spec_object import ReqIFSpecObject, SpecObjectAttribute  # type: ignore
    from reqif.models.reqif_spec_object_type import (  # type: ignore
        ReqIFSpecObjectType,
        SpecAttributeDefinition,
    )
    from reqif.models.reqif_specification import ReqIFSpecification  # type: ignore
    from reqif.models.reqif_specification_type import ReqIFSpecificationType  # type: ignore
    from reqif.models.reqif_types import SpecObjectAttributeType  # type: ignore
    from reqif.object_lookup import ReqIFObjectLookup  # type: ignore
    from reqif.reqif_bundle import ReqIFBundle  # type: ignore
    from reqif.unparser import ReqIFUnparser  # type: ignore

    now = _now_reqif_timestamp()

    with _connect(db_path) as conn:
        spec_ids = _get_spec_ids(conn)
        if not spec_ids:
            print("error: no specifications found in DB.", file=sys.stderr)
            return 2

        spec_id = args.spec_id
        if spec_id is None:
            if len(spec_ids) != 1:
                print(
                    f"error: DB has multiple specifications: {spec_ids}. Provide --spec-id.",
                    file=sys.stderr,
                )
                return 2
            spec_id = spec_ids[0]

        if spec_id not in spec_ids:
            print(f"error: spec-id not found: {spec_id}", file=sys.stderr)
            return 2

        spec_title = _load_spec_title(conn, spec_id)
        objects = _load_spec_objects(conn, spec_id)

        attrs_by_owner, dynamic_attr_names = _load_all_attributes_for_spec(conn, spec_id)

        # Datatypes.
        dt_string = ReqIFDataTypeDefinitionString(
            identifier=_reqif_id("DT-STRING"),
            long_name="SpecCompiler String",
            last_change=now,
            max_length=None,
        )
        dt_xhtml = ReqIFDataTypeDefinitionXHTML(
            identifier=_reqif_id("DT-XHTML"),
            long_name="SpecCompiler XHTML",
            last_change=now,
        )

        # Attribute definitions.
        def_pid = SpecAttributeDefinition.create(
            attribute_type=SpecObjectAttributeType.STRING,
            identifier=_reqif_id("AD-PID"),
            datatype_definition=dt_string.identifier,
            long_name="SpecCompiler.PID",
        )
        def_type = SpecAttributeDefinition.create(
            attribute_type=SpecObjectAttributeType.STRING,
            identifier=_reqif_id("AD-TYPE"),
            datatype_definition=dt_string.identifier,
            long_name="SpecCompiler.Type",
        )
        def_title = SpecAttributeDefinition.create(
            attribute_type=SpecObjectAttributeType.STRING,
            identifier=_reqif_id("AD-TITLE"),
            datatype_definition=dt_string.identifier,
            long_name="SpecCompiler.Title",
        )
        def_level = SpecAttributeDefinition.create(
            attribute_type=SpecObjectAttributeType.STRING,
            identifier=_reqif_id("AD-LEVEL"),
            datatype_definition=dt_string.identifier,
            long_name="SpecCompiler.Level",
        )
        def_body_text = SpecAttributeDefinition.create(
            attribute_type=SpecObjectAttributeType.STRING,
            identifier=_reqif_id("AD-BODY"),
            datatype_definition=dt_string.identifier,
            long_name="SpecCompiler.Body",
        )
        def_body_xhtml = SpecAttributeDefinition.create(
            attribute_type=SpecObjectAttributeType.XHTML,
            identifier=_reqif_id("AD-BODY-XHTML"),
            datatype_definition=dt_xhtml.identifier,
            long_name="SpecCompiler.BodyXHTML",
        )

        dynamic_defs: Dict[str, SpecAttributeDefinition] = {}
        for name in dynamic_attr_names:
            # Prototype: export all user attributes as string.
            dynamic_defs[name] = SpecAttributeDefinition.create(
                attribute_type=SpecObjectAttributeType.STRING,
                identifier=_reqif_id(f"AD-{_sanitize_attr_id(name)}"),
                datatype_definition=dt_string.identifier,
                long_name=name,
            )

        spec_object_type = ReqIFSpecObjectType.create(
            identifier=_reqif_id("SPEC-OBJECT-TYPE"),
            long_name="SpecCompiler Object",
            last_change=now,
            attribute_definitions=[
                def_pid,
                def_type,
                def_title,
                def_level,
                def_body_text,
                def_body_xhtml,
                *[dynamic_defs[n] for n in dynamic_attr_names],
            ],
        )

        specification_type = ReqIFSpecificationType(
            identifier=_reqif_id("SPECIFICATION-TYPE"),
            last_change=now,
            long_name="SpecCompiler Specification",
            spec_attributes=None,
            spec_attribute_map={},
            is_self_closed=True,
        )

        reqif_spec_objects: List[ReqIFSpecObject] = []
        reqif_spec_object_by_sd_id: Dict[str, ReqIFSpecObject] = {}

        for row in objects:
            values: List[SpecObjectAttribute] = []

            pid_value = row.pid or ""
            title_value = row.title_text or ""
            level_value = str(row.level or "")

            body_text = ""
            if row.ast:
                try:
                    blocks = json.loads(row.ast)
                    body_text = _pandoc_json_to_text(blocks).strip()
                except Exception:
                    body_text = row.ast

            body_xhtml = lxml_convert_to_reqif_ns_xhtml_string(
                _text_to_xhtml_div(body_text),
                reqif_xhtml=False,
            )

            values.append(
                SpecObjectAttribute(
                    attribute_type=SpecObjectAttributeType.STRING,
                    definition_ref=def_pid.identifier,
                    value=pid_value,
                )
            )
            values.append(
                SpecObjectAttribute(
                    attribute_type=SpecObjectAttributeType.STRING,
                    definition_ref=def_type.identifier,
                    value=row.type_ref,
                )
            )
            values.append(
                SpecObjectAttribute(
                    attribute_type=SpecObjectAttributeType.STRING,
                    definition_ref=def_title.identifier,
                    value=title_value,
                )
            )
            values.append(
                SpecObjectAttribute(
                    attribute_type=SpecObjectAttributeType.STRING,
                    definition_ref=def_level.identifier,
                    value=level_value,
                )
            )
            values.append(
                SpecObjectAttribute(
                    attribute_type=SpecObjectAttributeType.STRING,
                    definition_ref=def_body_text.identifier,
                    value=body_text,
                )
            )
            values.append(
                SpecObjectAttribute(
                    attribute_type=SpecObjectAttributeType.XHTML,
                    definition_ref=def_body_xhtml.identifier,
                    value=body_xhtml,
                    value_stripped_xhtml=None,
                )
            )

            dyn = attrs_by_owner.get(row.identifier, {})
            for name in dynamic_attr_names:
                if name not in dyn:
                    continue
                values.append(
                    SpecObjectAttribute(
                        attribute_type=SpecObjectAttributeType.STRING,
                        definition_ref=dynamic_defs[name].identifier,
                        value=dyn[name],
                    )
                )

            reqif_obj = ReqIFSpecObject(
                identifier=f"_{row.identifier}",
                attributes=values,
                spec_object_type=spec_object_type.identifier,
                long_name=title_value or pid_value or row.identifier,
                last_change=now,
            )
            reqif_spec_objects.append(reqif_obj)
            reqif_spec_object_by_sd_id[row.identifier] = reqif_obj

        # Build hierarchy.
        hierarchy_tree = _build_spec_hierarchy(objects)

        def make_hierarchy_nodes(
            nodes: List[Tuple[SpecObjectRow, List]],
        ) -> List[ReqIFSpecHierarchy]:
            out_nodes: List[ReqIFSpecHierarchy] = []
            for sd_row, children in nodes:
                sd_level = sd_row.level or 2
                hier_level = max(1, int(sd_level) - 1)
                reqif_obj = reqif_spec_object_by_sd_id[sd_row.identifier]
                out_nodes.append(
                    ReqIFSpecHierarchy(
                        xml_node=None,
                        is_self_closed=False,
                        identifier=_reqif_id("SPEC-HIERARCHY"),
                        last_change=now,
                        long_name=None,
                        spec_object=reqif_obj.identifier,
                        children=make_hierarchy_nodes(children),
                        ref_then_children_order=True,
                        level=hier_level,
                    )
                )
            return out_nodes

        specification = ReqIFSpecification(
            identifier=_reqif_id("SPECIFICATION"),
            last_change=now,
            long_name=spec_title,
            # Keep empty VALUES to satisfy strict schema validators.
            values=[],
            specification_type=specification_type.identifier,
            children=make_hierarchy_nodes(hierarchy_tree),
        )

        reqif_content = ReqIFReqIFContent(
            data_types=[dt_string, dt_xhtml],
            spec_types=[specification_type, spec_object_type],
            spec_objects=reqif_spec_objects,
            spec_relations=[],
            specifications=[specification],
            spec_relation_groups=[],
        )

        bundle = ReqIFBundle(
            namespace_info=ReqIFNamespaceInfo.create_default(),
            req_if_header=ReqIFReqIFHeader(
                identifier=_reqif_id("REQ-IF-HEADER"),
                creation_time=now,
                repository_id="speccompiler",
                req_if_tool_id="speccompiler-export-reqif-prototype",
                req_if_version="1.0",
                source_tool_id="speccompiler",
                title=f"SpecCompiler export: {spec_title}",
            ),
            core_content=ReqIFCoreContent(req_if_content=reqif_content),
            tool_extensions_tag_exists=False,
            lookup=ReqIFObjectLookup.empty(),
            exceptions=[],
        )

        out_xml = ReqIFUnparser.unparse(bundle)

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(out_xml)

    print(f"Wrote ReqIF: {out_path}")
    print(f"SpecCompiler spec_id: {spec_id}")
    print(f"Objects: {len(objects)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
